#include "mqtt_client.h"

#include <Arduino.h>
#include <ArduinoJson.h>
#include <PubSubClient.h>
#include <WiFi.h>
#include <time.h>

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

#include "config.h"

static WiFiClient wifiClient;
static PubSubClient mqtt(wifiClient);

static QueueHandle_t outQueue = nullptr;      // events + trials (kept while offline)
static QueueHandle_t captureQueue = nullptr;  // capture requests (immediate or never)
static QueueHandle_t commandQueue = nullptr;  // backend -> device

struct CaptureReq {
  char requestId[24];
  char trigger[12];
  char zone[20];
  uint32_t eventEpoch;
  uint32_t queuedMs;
};

static volatile bool online = false;
// 0 = WiFi down, 1 = WiFi up but MQTT down, 2 = fully online.
static volatile uint8_t netStageValue = 0;
static char clientId[40];

// ---------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------

uint32_t netEpochNow() {
  const time_t t = time(nullptr);
  return t > 1700000000 ? (uint32_t)t : 0;  // before NTP sync the clock is near 1970
}

// ---------------------------------------------------------------------------
// Public API (called from loop() on core 1)
// ---------------------------------------------------------------------------

bool netIsOnline() { return online; }

const char *netStage() {
  switch (netStageValue) {
    case 2: return "ONLINE";
    case 1: return "OFFLINE(mqtt)";
    default: return "OFFLINE(wifi)";
  }
}

void netEnqueue(const OutRec &rec) {
  if (!outQueue) return;
  if (xQueueSend(outQueue, &rec, 0) != pdTRUE) {
    OutRec dropped;
    xQueueReceive(outQueue, &dropped, 0);  // drop the oldest
    xQueueSend(outQueue, &rec, 0);
  }
}

uint32_t netQueued() { return outQueue ? (uint32_t)uxQueueMessagesWaiting(outQueue) : 0; }

bool netSendCaptureRequest(const char *requestId, const char *trigger, const char *zone, uint32_t eventEpoch) {
  if (!online || !captureQueue || eventEpoch == 0) return false;
  CaptureReq r{};
  strlcpy(r.requestId, requestId, sizeof r.requestId);
  strlcpy(r.trigger, trigger, sizeof r.trigger);
  strlcpy(r.zone, zone, sizeof r.zone);
  r.eventEpoch = eventEpoch;
  r.queuedMs = millis();
  return xQueueSend(captureQueue, &r, 0) == pdTRUE;
}

bool netPollCommand(DeviceCommand &out) {
  return commandQueue && xQueueReceive(commandQueue, &out, 0) == pdTRUE;
}

// ---------------------------------------------------------------------------
// Diagnostics: turn numeric codes into words so Serial alone explains failures
// ---------------------------------------------------------------------------

static const char *wifiStatusName(wl_status_t s) {
  switch (s) {
    case WL_NO_SHIELD: return "WL_NO_SHIELD";
    case WL_IDLE_STATUS: return "WL_IDLE_STATUS (waiting/connecting)";
    case WL_NO_SSID_AVAIL: return "WL_NO_SSID_AVAIL (network name not found)";
    case WL_SCAN_COMPLETED: return "WL_SCAN_COMPLETED";
    case WL_CONNECTED: return "WL_CONNECTED";
    case WL_CONNECT_FAILED: return "WL_CONNECT_FAILED (wrong password / rejected)";
    case WL_CONNECTION_LOST: return "WL_CONNECTION_LOST";
    case WL_DISCONNECTED: return "WL_DISCONNECTED";
    default: return "WL_UNKNOWN";
  }
}

static const char *wifiReasonName(uint8_t reason) {
  switch (reason) {
    case 2: return "AUTH_EXPIRE";
    case 6:
    case 7: return "NOT_AUTHED/NOT_ASSOCED";
    case 8: return "ASSOC_LEAVE";
    case 15: return "4WAY_HANDSHAKE_TIMEOUT (usually WRONG PASSWORD)";
    case 23: return "802.1X_AUTH_FAILED";
    case 200: return "BEACON_TIMEOUT (signal lost)";
    case 201: return "NO_AP_FOUND (SSID not visible: wrong name, out of range, or 5 GHz only)";
    case 202: return "AUTH_FAIL (wrong password / security mode)";
    case 203: return "ASSOC_FAIL";
    case 204: return "HANDSHAKE_TIMEOUT (usually WRONG PASSWORD)";
    case 205: return "CONNECTION_FAIL";
    default: return "see the esp_wifi disconnect-reason table";
  }
}

static const char *mqttStateName(int state) {
  switch (state) {
    case -4: return "CONNECTION_TIMEOUT (broker did not answer in time)";
    case -3: return "CONNECTION_LOST";
    case -2: return "CONNECT_FAILED (could not open a TCP connection to the broker)";
    case -1: return "DISCONNECTED";
    case 0: return "CONNECTED";
    case 1: return "CONNECT_BAD_PROTOCOL";
    case 2: return "CONNECT_BAD_CLIENT_ID";
    case 3: return "CONNECT_UNAVAILABLE (broker refused: unavailable)";
    case 4: return "CONNECT_BAD_CREDENTIALS";
    case 5: return "CONNECT_UNAUTHORIZED (broker needs a username/password)";
    default: return "UNKNOWN";
  }
}

static void onWifiEvent(arduino_event_id_t event, arduino_event_info_t info) {
  switch (event) {
    case ARDUINO_EVENT_WIFI_STA_CONNECTED:
      Serial.printf("[WIFI] associated with the access point (channel %u)\n",
                    (unsigned)info.wifi_sta_connected.channel);
      break;
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      Serial.printf("[WIFI] got IP %s  gateway %s  RSSI %d dBm\n", WiFi.localIP().toString().c_str(),
                    WiFi.gatewayIP().toString().c_str(), WiFi.RSSI());
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
      Serial.printf("[WIFI] disconnected, reason %u = %s\n", (unsigned)info.wifi_sta_disconnected.reason,
                    wifiReasonName(info.wifi_sta_disconnected.reason));
      break;
    default:
      break;
  }
}

// ESP32 radios are 2.4 GHz only. List what it can see and say whether the
// configured network is among them.
static void scanAndReport() {
  Serial.println(F("[WIFI] scanning for networks the ESP32 can see (2.4 GHz only)..."));
  const int n = WiFi.scanNetworks();
  if (n <= 0) {
    Serial.println(F("[WIFI] scan found NO networks: check antenna, power and range."));
    WiFi.scanDelete();
    return;
  }
  bool found = false;
  for (int i = 0; i < n && i < 15; i++) {
    const bool match = WiFi.SSID(i) == String(WIFI_SSID);
    found = found || match;
    Serial.printf("[WIFI]   %2d. \"%s\"  ch %d  %d dBm  %s%s\n", i + 1, WiFi.SSID(i).c_str(),
                  (int)WiFi.channel(i), (int)WiFi.RSSI(i),
                  WiFi.encryptionType(i) == WIFI_AUTH_OPEN ? "open" : "secured",
                  match ? "   <== your WIFI_SSID" : "");
  }
  WiFi.scanDelete();
  if (found) {
    Serial.println(F("[WIFI] your network IS visible, so a failure is the password or the router."));
  } else {
    Serial.printf("[WIFI] \"%s\" is NOT visible to the ESP32.\n", WIFI_SSID);
    Serial.println(F("[WIFI]   - Names containing '5G' / '5GHz' are 5 GHz networks; ESP32 cannot see them."));
    Serial.println(F("[WIFI]   - Use the router's 2.4 GHz name, or a phone hotspot set to 2.4 GHz."));
    Serial.println(F("[WIFI]   - Check the name is spelled exactly (case and spaces matter)."));
  }
}

static void checkSubnet() {
  IPAddress broker;
  if (!broker.fromString(MQTT_HOST)) {
    Serial.printf("[NET] MQTT_HOST \"%s\" is not a plain IPv4 address.\n", MQTT_HOST);
    return;
  }
  const IPAddress me = WiFi.localIP();
  const IPAddress mask = WiFi.subnetMask();
  bool same = true;
  for (int i = 0; i < 4; i++) same = same && ((me[i] & mask[i]) == (broker[i] & mask[i]));
  if (!same) {
    Serial.printf("[NET] WARNING: broker %s is on a DIFFERENT subnet than this device (%s / %s). "
                  "Use the laptop's IPv4 on THIS Wi-Fi.\n",
                  MQTT_HOST, me.toString().c_str(), mask.toString().c_str());
  }
}

// ---------------------------------------------------------------------------
// Incoming commands (net task)
// ---------------------------------------------------------------------------

static void onMessage(char *topic, uint8_t *payload, unsigned int length) {
  if (strcmp(topic, TOPIC_CMD) != 0) return;
  Serial.printf("[MQTT] rx cmd: %.*s\n", (int)(length > 240 ? 240 : length), (const char *)payload);
  JsonDocument doc;
  if (deserializeJson(doc, payload, length)) {
    Serial.println(F("[MQTT] cmd ignored: not valid JSON"));
    return;
  }
  const char *device = doc["device_id"] | "";
  if (strcmp(device, DEVICE_ID) != 0) {
    Serial.printf("[MQTT] cmd ignored: device_id '%s' is not '%s'\n", device, DEVICE_ID);
    return;
  }
  const char *action = doc["action"] | "";
  // "deterrent" = a manual test trial; "classification" = the camera's species answer
  // for a capture request (it is attached to the running trial, never starts one).
  if (strcmp(action, "deterrent") != 0 && strcmp(action, "classification") != 0) {
    Serial.printf("[MQTT] cmd ignored: unsupported action '%s' (supported: deterrent, classification)\n", action);
    return;
  }
  DeviceCommand c{};
  strlcpy(c.action, action, sizeof c.action);
  strlcpy(c.source, doc["source"] | "manual", sizeof c.source);
  JsonObject params = doc["params"];
  strlcpy(c.condition, params["condition"] | "", sizeof c.condition);
  strlcpy(c.species, params["species"] | "", sizeof c.species);
  strlcpy(c.requestId, params["request_id"] | "", sizeof c.requestId);
  c.confidence = params["confidence"] | 0.0f;
  xQueueSend(commandQueue, &c, 0);
}

// ---------------------------------------------------------------------------
// Publishing (net task only)
// ---------------------------------------------------------------------------

static void isoTime(uint32_t epoch, char *out, size_t n) {
  const time_t t = (time_t)epoch;
  struct tm tmUtc;
  gmtime_r(&t, &tmUtc);
  strftime(out, n, "%Y-%m-%dT%H:%M:%SZ", &tmUtc);
}

// Epoch for a record: its own, or back-dated from uptime once the clock is synced.
// Returns 0 if it cannot be known yet (caller keeps the record).
static uint32_t resolveEpoch(uint32_t epoch, uint32_t ms) {
  if (epoch != 0) return epoch;
  const uint32_t now = netEpochNow();
  if (now == 0) return 0;
  return now - (millis() - ms) / 1000;
}

// PestEvent, exactly the backend's field set and order. The camera has not looked
// yet (yolo_pred null, camera_in_view false): the backend fills them in after the
// photo is classified.
static bool publishEvent(const OutRec &r, uint32_t epoch) {
  char ts[24];
  isoTime(epoch, ts, sizeof ts);
  JsonDocument doc;
  doc["schema_version"] = SCHEMA_VERSION;
  doc["device_id"] = DEVICE_ID;
  doc["ts"] = ts;
  doc["zone"] = r.zone;
  doc["trigger_source"] = r.trigger;
  doc["pir"] = r.pir;
  doc["vib_rms_g"] = r.vibRmsG;  // 0.0 / 1.0 placeholder (digital sensor)
  doc["vib_trigger"] = r.vibTrigger;
  doc["ambient_lux"] = 0.0;      // placeholder: this unit has no light sensor
  doc["camera_in_view"] = false;
  doc["yolo_pred"] = nullptr;
  doc["yolo_conf"] = nullptr;
  char buf[420];
  const size_t n = serializeJson(doc, buf, sizeof buf);
  return mqtt.publish(TOPIC_EVENT, (const uint8_t *)buf, n, false);
}

// DeterrenceTrial. system_verdict stays "uncertain" (no vision confirms the exit;
// a person reviews it in the app). species is the camera's answer if it arrived while the trial was running, else null.
static bool publishTrial(const OutRec &r, uint32_t epoch) {
  char ts[24];
  isoTime(epoch, ts, sizeof ts);
  JsonDocument doc;
  doc["schema_version"] = SCHEMA_VERSION;
  doc["trial_id"] = r.trialId;
  doc["device_id"] = DEVICE_ID;
  if (r.species[0]) doc["species"] = r.species;
  else doc["species"] = nullptr;
  doc["condition"] = r.condition;
  doc["zone"] = r.zone;
  doc["activation_s"] = r.activationS;
  doc["observation_window_s"] = r.observationS;
  doc["exited"] = nullptr;
  doc["time_to_leave_s"] = nullptr;
  doc["system_verdict"] = "uncertain";
  doc["ts"] = ts;
  char buf[480];
  const size_t n = serializeJson(doc, buf, sizeof buf);
  return mqtt.publish(TOPIC_EVENT, (const uint8_t *)buf, n, false);
}

static bool publishCaptureRequest(const CaptureReq &c) {
  char ts[24], eventTs[24];
  isoTime(netEpochNow(), ts, sizeof ts);
  isoTime(c.eventEpoch, eventTs, sizeof eventTs);
  JsonDocument doc;
  doc["schema_version"] = SCHEMA_VERSION;
  doc["device_id"] = DEVICE_ID;
  doc["request_id"] = c.requestId;
  doc["ts"] = ts;
  doc["event_ts"] = eventTs;  // identifies the PestEvent this photo belongs to
  doc["trigger_source"] = c.trigger;
  doc["zone"] = c.zone;
  char buf[320];
  const size_t n = serializeJson(doc, buf, sizeof buf);
  return mqtt.publish(TOPIC_CAPTURE_REQUEST, (const uint8_t *)buf, n, false);
}

static bool connectMqtt() {
  const char *user = strlen(MQTT_USER) ? MQTT_USER : nullptr;
  const char *pass = strlen(MQTT_PASS) ? MQTT_PASS : nullptr;
  Serial.printf("[MQTT] connecting to %s:%d as '%s' ...\n", MQTT_HOST, MQTT_PORT, clientId);
  // Last Will: the broker publishes "offline" (retained) if we vanish.
  if (!mqtt.connect(clientId, user, pass, TOPIC_STATUS, 1, true, "{\"status\":\"offline\"}", true)) {
    const int st = mqtt.state();
    Serial.printf("[MQTT] connect FAILED, state %d = %s\n", st, mqttStateName(st));
    if (st == -2 || st == -4) {
      Serial.println(F("[MQTT]   check: MQTT_HOST is the laptop's current IPv4 (ipconfig);"));
      Serial.println(F("[MQTT]   the broker listens on 0.0.0.0:1883 (not only 127.0.0.1);"));
      Serial.println(F("[MQTT]   Windows Firewall allows inbound TCP 1883; same Wi-Fi/subnet."));
    }
    return false;
  }
  mqtt.subscribe(TOPIC_CMD, 1);
  mqtt.publish(TOPIC_STATUS, "{\"status\":\"online\"}", true);  // retained
  Serial.printf("[MQTT] connected, subscribed to %s, status 'online' published (retained)\n", TOPIC_CMD);
  return true;
}

// ---------------------------------------------------------------------------
// Network task (core 0). Never blocks sensing or the deterrent on core 1.
// ---------------------------------------------------------------------------

static void netTask(void *) {
  Serial.printf("[NET] network task started. WiFi SSID \"%s\" (%u chars), password %u chars, broker %s:%d\n",
                WIFI_SSID, (unsigned)strlen(WIFI_SSID), (unsigned)strlen(WIFI_PASSWORD), MQTT_HOST, MQTT_PORT);

  WiFi.persistent(false);
  WiFi.onEvent(onWifiEvent);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);  // power-save drops keepalives and adds latency to the capture request
  WiFi.setAutoReconnect(true);

  scanAndReport();

  Serial.printf("[WIFI] connecting to \"%s\" ...\n", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  bool ntpStarted = false;
  bool wasOnline = false;
  bool wifiAnnounced = false;
  bool havePending = false;
  OutRec pending{};
  uint32_t lastWifiTry = millis();
  uint32_t lastMqttTry = 0;
  uint32_t lastStatusLog = 0;
  uint32_t lastRescan = millis();
  int wifiFailures = 0;

  for (;;) {
    const uint32_t now = millis();
    const wl_status_t wl = WiFi.status();

    if (wl != WL_CONNECTED) {
      netStageValue = 0;
      online = false;
      wifiAnnounced = false;
      if (wasOnline) {
        Serial.println(F("[NET] now OFFLINE: WiFi lost. Sensing and the deterrent keep working locally; "
                         "events are queued."));
        wasOnline = false;
      }
      if (now - lastStatusLog >= 5000) {
        lastStatusLog = now;
        Serial.printf("[WIFI] waiting for connection, status = %s\n", wifiStatusName(wl));
      }
      if (now - lastWifiTry >= WIFI_RETRY_MS) {
        lastWifiTry = now;
        wifiFailures++;
        Serial.printf("[WIFI] attempt %d did not connect (%s); retrying\n", wifiFailures, wifiStatusName(wl));
        if (wifiFailures % 3 == 0 && now - lastRescan > 30000) {
          lastRescan = now;
          scanAndReport();
        }
        WiFi.disconnect();
        WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
      }
      vTaskDelay(pdMS_TO_TICKS(250));
      continue;
    }

    if (!wifiAnnounced) {
      wifiAnnounced = true;
      wifiFailures = 0;
      Serial.printf("[WIFI] connected: IP %s, RSSI %d dBm\n", WiFi.localIP().toString().c_str(), WiFi.RSSI());
      checkSubnet();
    }
    if (!ntpStarted) {
      configTime(0, 0, "pool.ntp.org", "time.google.com");  // UTC
      Serial.println(F("[NET] NTP sync started (needed for event timestamps)"));
      ntpStarted = true;
    }

    if (!mqtt.connected()) {
      netStageValue = 1;
      online = false;
      if (wasOnline) {
        Serial.printf("[NET] now OFFLINE: MQTT session lost (state %d = %s)\n", mqtt.state(),
                      mqttStateName(mqtt.state()));
        wasOnline = false;
      }
      if (now - lastMqttTry >= MQTT_RETRY_MS) {
        lastMqttTry = now;
        connectMqtt();
      }
      // A capture request that could not be sent is useless later: discard.
      CaptureReq stale;
      while (xQueueReceive(captureQueue, &stale, 0) == pdTRUE) {
      }
      vTaskDelay(pdMS_TO_TICKS(100));
      continue;
    }

    netStageValue = 2;
    online = true;
    if (!wasOnline) {
      wasOnline = true;
      Serial.printf("[NET] ONLINE. %u queued event/trial record(s) will be sent now.\n", (unsigned)netQueued());
    }
    mqtt.loop();

    // 1) Capture requests first: they are time critical (the 3 s window).
    CaptureReq cr;
    while (xQueueReceive(captureQueue, &cr, 0) == pdTRUE) {
      if (millis() - cr.queuedMs > 2000) {
        Serial.printf("[MQTT] capture request %s dropped: too old to be useful\n", cr.requestId);
        continue;
      }
      if (publishCaptureRequest(cr)) {
        Serial.printf("[MQTT] capture request %s sent (%s, %s)\n", cr.requestId, cr.trigger, cr.zone);
      } else {
        Serial.printf("[MQTT] capture request %s FAILED to publish\n", cr.requestId);
      }
      mqtt.loop();
    }

    // 2) Events and trials. A record is removed only after publish() succeeded.
    for (int sent = 0; sent < 10; sent++) {
      if (!havePending) {
        if (xQueueReceive(outQueue, &pending, 0) != pdTRUE) break;
        havePending = true;
      }
      const uint32_t epoch = resolveEpoch(pending.epoch, pending.ms);
      if (epoch == 0) {
        if (now - lastStatusLog >= 5000) {
          lastStatusLog = now;
          Serial.println(F("[NET] holding queued records: clock not synced yet (NTP)"));
        }
        break;
      }
      const bool ok = pending.kind == OUT_EVENT ? publishEvent(pending, epoch) : publishTrial(pending, epoch);
      if (!ok) break;
      Serial.printf("[MQTT] %s published%s\n", pending.kind == OUT_EVENT ? "event" : "trial",
                    pending.epoch == 0 ? " (back-dated from before the clock was synced)" : "");
      havePending = false;
      mqtt.loop();
    }

    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void netBegin() {
  outQueue = xQueueCreate(OUT_QUEUE_LEN, sizeof(OutRec));
  captureQueue = xQueueCreate(4, sizeof(CaptureReq));
  commandQueue = xQueueCreate(8, sizeof(DeviceCommand));

  snprintf(clientId, sizeof clientId, "kg-%s-%06X", DEVICE_ID, (unsigned)((ESP.getEfuseMac() >> 24) & 0xFFFFFF));

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(512);
  mqtt.setKeepAlive(15);
  mqtt.setSocketTimeout(2);
  mqtt.setCallback(onMessage);

  xTaskCreatePinnedToCore(netTask, "kg-net", 8192, nullptr, 1, nullptr, 0);
}
