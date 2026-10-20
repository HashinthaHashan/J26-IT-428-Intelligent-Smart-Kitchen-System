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

static QueueHandle_t sampleQueue = nullptr;
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

bool netWifiUp() { return WiFi.status() == WL_CONNECTED; }

void netEnqueue(const CameraSample &s) {
  if (!sampleQueue) return;
  if (xQueueSend(sampleQueue, &s, 0) != pdTRUE) {
    CameraSample dropped;
    xQueueReceive(sampleQueue, &dropped, 0);  // drop the oldest
    xQueueSend(sampleQueue, &s, 0);
  }
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
      Serial.printf("[WIFI] got IP %s  gateway %s  RSSI %d dBm\n",
                    WiFi.localIP().toString().c_str(), WiFi.gatewayIP().toString().c_str(),
                    WiFi.RSSI());
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
      Serial.printf("[WIFI] disconnected, reason %u = %s\n",
                    (unsigned)info.wifi_sta_disconnected.reason,
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
// Publishing (net task only)
// ---------------------------------------------------------------------------

// Builds ONE camera-features message. This is a NEW message type on its own topic
// (.../camera); the backend does not store it yet (see README, open decisions).
static void addItem(JsonArray items, const char *compartment, const ColorFeatures &f) {
  JsonObject o = items.add<JsonObject>();
  o["compartment"] = compartment;
  o["valid"] = f.valid;
  if (f.valid) {
    o["hue_mean"] = roundf(f.hueMean * 10.0f) / 10.0f;
    o["brown_pct"] = roundf(f.brownPct * 10.0f) / 10.0f;
    o["green_pct"] = roundf(f.greenPct * 10.0f) / 10.0f;
  } else {
    o["hue_mean"] = nullptr;
    o["brown_pct"] = nullptr;
    o["green_pct"] = nullptr;
  }
  o["coverage_pct"] = roundf(f.coveragePct * 10.0f) / 10.0f;
}

static bool publishCapture(const CameraSample &s, uint32_t epoch) {
  const time_t t = (time_t)epoch;
  struct tm tmUtc;
  gmtime_r(&t, &tmUtc);
  char ts[24];
  strftime(ts, sizeof ts, "%Y-%m-%dT%H:%M:%SZ", &tmUtc);

  JsonDocument doc;
  doc["schema_version"] = SCHEMA_VERSION;
  doc["device_id"] = DEVICE_ID;
  doc["ts"] = ts;
  doc["frame_w"] = s.width;
  doc["frame_h"] = s.height;
  doc["roi_mode"] = s.split ? "split" : "combined";
  JsonArray items = doc["items"].to<JsonArray>();
  addItem(items, "banana", s.banana);
  addItem(items, "potato", s.potato);

  char buf[512];
  const size_t n = serializeJson(doc, buf, sizeof buf);
  return mqtt.publish(TOPIC_CAMERA, (const uint8_t *)buf, n, false);
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
  mqtt.publish(TOPIC_STATUS, "{\"status\":\"online\"}", true);  // retained
  Serial.println(F("[MQTT] connected, camera_status 'online' published (retained)"));
  return true;
}

// ---------------------------------------------------------------------------
// Network task (core 0). Never blocks sensing on core 1.
// ---------------------------------------------------------------------------

static void netTask(void *) {
  Serial.printf("[NET] network task started. WiFi SSID \"%s\" (%u chars), password %u chars, "
                "broker %s:%d\n",
                WIFI_SSID, (unsigned)strlen(WIFI_SSID), (unsigned)strlen(WIFI_PASSWORD),
                MQTT_HOST, MQTT_PORT);

  WiFi.persistent(false);
  WiFi.onEvent(onWifiEvent);
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);  // power-save drops keepalives and causes flapping
  WiFi.setAutoReconnect(true);

  scanAndReport();

  Serial.printf("[WIFI] connecting to \"%s\" ...\n", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  bool ntpStarted = false;
  bool wasOnline = false;
  bool wifiAnnounced = false;
  bool havePending = false;
  CameraSample pending{};
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
        Serial.println(F("[NET] now OFFLINE: WiFi lost. Captures are queued and sent on reconnect."));
        wasOnline = false;
      }
      if (now - lastStatusLog >= 5000) {
        lastStatusLog = now;
        Serial.printf("[WIFI] waiting for connection, status = %s\n", wifiStatusName(wl));
      }
      if (now - lastWifiTry >= WIFI_RETRY_MS) {
        lastWifiTry = now;
        wifiFailures++;
        Serial.printf("[WIFI] attempt %d did not connect (%s); retrying\n", wifiFailures,
                      wifiStatusName(wl));
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
      Serial.printf("[WIFI] connected: IP %s, RSSI %d dBm\n", WiFi.localIP().toString().c_str(),
                    WiFi.RSSI());
      checkSubnet();
    }
    if (!ntpStarted) {
      configTime(0, 0, "pool.ntp.org", "time.google.com");  // UTC
      Serial.println(F("[NET] NTP sync started (needed for telemetry timestamps)"));
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
      vTaskDelay(pdMS_TO_TICKS(100));
      continue;
    }

    netStageValue = 2;
    online = true;
    if (!wasOnline) {
      wasOnline = true;
      Serial.printf("[NET] ONLINE. %u capture(s) queued from while offline will be sent now.\n",
                    (unsigned)uxQueueMessagesWaiting(sampleQueue));
    }
    mqtt.loop();

    // Flush queued captures. A capture is only removed after publish() succeeded.
    for (int sent = 0; sent < 5; sent++) {
      if (!havePending) {
        if (xQueueReceive(sampleQueue, &pending, 0) != pdTRUE) break;
        havePending = true;
      }
      uint32_t epoch = pending.epoch;
      if (epoch == 0) {  // captured before the first NTP sync: back-date from uptime
        const uint32_t nowEpoch = netEpochNow();
        if (nowEpoch == 0) {
          if (now - lastStatusLog >= 5000) {
            lastStatusLog = now;
            Serial.println(F("[NET] holding capture: clock not synced yet (NTP)"));
          }
          break;
        }
        epoch = nowEpoch - (millis() - pending.ms) / 1000;
      }
      if (!publishCapture(pending, epoch)) break;
      Serial.println(F("[MQTT] camera features published"));
      havePending = false;
      mqtt.loop();
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

void netBegin() {
  sampleQueue = xQueueCreate(QUEUE_LEN, sizeof(CameraSample));

  snprintf(clientId, sizeof clientId, "kg-%s-camera-%06X", DEVICE_ID,
           (unsigned)((ESP.getEfuseMac() >> 24) & 0xFFFFFF));

  mqtt.setServer(MQTT_HOST, MQTT_PORT);
  mqtt.setBufferSize(512);
  mqtt.setKeepAlive(30);  // slow cadence: relax keepalive vs the LPG board
  mqtt.setSocketTimeout(2);

  xTaskCreatePinnedToCore(netTask, "kg-net", 8192, nullptr, 1, nullptr, 0);
}
