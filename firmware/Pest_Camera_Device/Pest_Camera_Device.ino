// =============================================================================
// KitchenGuard - Component 03: Pest detection, BOARD 2 (ESP32-CAM)
//
// Idle until the backend relays a capture order (it received a PIR/vibration request
// from the sensor board). Then, as fast as possible:
//
//   1. capture ONE photo
//   2. POST it over HTTP to the backend  (/api/pest/pest-kitchen01/photo)
//   3. publish capture_done over MQTT   (was the upload accepted?)
//
// The backend runs YOLO on the photo, fills in the PestEvent's species and, if the
// answer is quick enough, orders the sensor board's deterrent. This board never
// talks to the sensor board and has no sensors of its own.
//
// Why HTTP for the image: a JPEG is ~30-60 KB (an RGB565 frame 150 KB). MQTT would
// need base64 (+33 %) inside a message far above the broker/client buffer limits and
// would block the keep-alive; an HTTP POST streams the bytes and returns the
// classification in the reply.
// =============================================================================

#include <Arduino.h>
#include <WiFi.h>
#include <esp_system.h>

#include "camera.h"
#include "config.h"
#include "mqtt_client.h"

static uint32_t lastCaptureEndMs = 0;
static bool anyCapture = false;
static int consecutiveFailures = 0;
static uint32_t okCount = 0, failCount = 0, skippedCount = 0;
static uint32_t nextHeartbeatMs = 0;

static void logResetReason() {
  const esp_reset_reason_t r = esp_reset_reason();
  const char *name = "UNKNOWN";
  switch (r) {
    case ESP_RST_POWERON: name = "POWER-ON (normal cold start)"; break;
    case ESP_RST_SW: name = "software restart"; break;
    case ESP_RST_PANIC: name = "PANIC (crash)"; break;
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT: name = "WATCHDOG (a task hung)"; break;
    case ESP_RST_BROWNOUT: name = "BROWNOUT (power rail dropped! the camera needs a solid 5 V)"; break;
    default: break;
  }
  Serial.printf("[BOOT] reset reason: %s\n", name);
}

static void ack(const char *requestId, const UploadResult &r) {
  DoneMsg d{};
  strlcpy(d.requestId, requestId, sizeof d.requestId);
  d.uploadOk = r.uploadOk;
  d.rgb565 = r.rgb565;
  d.bytes = r.bytes;
  strlcpy(d.detail, r.detail, sizeof d.detail);
  netPublishDone(d);
}

static void handleOrder(const CaptureOrder &o) {
  const uint32_t now = millis();
  UploadResult skipped = {};
  skipped.rgb565 = CAMERA_USE_RGB565;

  if (now - o.receivedMs > MAX_ORDER_AGE_MS) {
    skippedCount++;
    strlcpy(skipped.detail, "order too old (camera was busy)", sizeof skipped.detail);
    Serial.printf("[%5lus] ORDER %s skipped: waited %lu ms (older than %d ms)\n", (unsigned long)(now / 1000),
                  o.requestId, (unsigned long)(now - o.receivedMs), MAX_ORDER_AGE_MS);
    ack(o.requestId, skipped);
    return;
  }
  if (anyCapture && now - lastCaptureEndMs < MIN_CAPTURE_GAP_MS) {
    skippedCount++;
    strlcpy(skipped.detail, "too soon after the previous photo", sizeof skipped.detail);
    Serial.printf("[%5lus] ORDER %s skipped: previous photo was %lu ms ago (min %d ms)\n",
                  (unsigned long)(now / 1000), o.requestId, (unsigned long)(now - lastCaptureEndMs),
                  MIN_CAPTURE_GAP_MS);
    ack(o.requestId, skipped);
    return;
  }

  Serial.printf("[%5lus] ORDER %s: capturing...\n", (unsigned long)(now / 1000), o.requestId);
  const UploadResult r = cameraCaptureAndUpload(o.requestId);
  lastCaptureEndMs = millis();
  anyCapture = true;

  if (r.uploadOk) {
    okCount++;
    consecutiveFailures = 0;
    Serial.printf("[%5lus] ORDER %s DONE: %u bytes (%s) | capture %lu ms + upload %lu ms | backend says: %s\n",
                  (unsigned long)(lastCaptureEndMs / 1000), o.requestId, (unsigned)r.bytes,
                  r.rgb565 ? "RGB565 uncompressed" : "JPEG", (unsigned long)r.captureMs,
                  (unsigned long)r.uploadMs, r.label[0] ? r.label : "no classification (model not loaded?)");
  } else {
    failCount++;
    Serial.printf("[%5lus] ORDER %s FAILED: %s (capture %lu ms, upload %lu ms, http %d)\n",
                  (unsigned long)(lastCaptureEndMs / 1000), o.requestId, r.detail, (unsigned long)r.captureMs,
                  (unsigned long)r.uploadMs, r.httpCode);
    // Only a camera/capture fault counts toward a restart, not a network/backend fault.
    if (!r.captured) {
      consecutiveFailures++;
      if (consecutiveFailures == 3) {
        Serial.println(F("[CAM] 3 capture failures in a row: re-initialising the camera."));
        cameraReinit();
      } else if (consecutiveFailures >= 6) {
        Serial.println(F("[CAM] 6 capture failures in a row: restarting the board."));
        delay(200);
        ESP.restart();
      }
    }
  }
  ack(o.requestId, r);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println(F("=== KitchenGuard pest CAMERA board, device " DEVICE_ID " ==="));
  logResetReason();

  // GPIO4 is the built-in flash LED: off unless USE_FLASH_LED asks for it.
  pinMode(PIN_FLASH_LED, OUTPUT);
  digitalWrite(PIN_FLASH_LED, LOW);

  Serial.printf("[HW] sensor path: %s %s | photos -> http://%s:%d%s | WiFi '%s' -> MQTT %s:%d\n",
                CAMERA_USE_RGB565 ? "RGB565 (RHYX-M21-45 mode)" : "JPEG (OV2640 mode)",
                CAMERA_USE_RGB565 ? "QVGA 320x240, uploaded uncompressed" : "VGA 640x480", API_HOST, API_PORT,
                API_PHOTO_PATH, WIFI_SSID, MQTT_HOST, MQTT_PORT);

  if (!cameraBegin()) {
    Serial.println(F("[CAM] Camera is NOT running: capture orders will be refused. Fix the cause above and reset."));
  }

  netBegin();  // network runs on its own task; the capture below never blocks MQTT
  nextHeartbeatMs = millis() + 30000;
}

void loop() {
  CaptureOrder o;
  if (netPollOrder(o)) {
    if (!cameraReady()) {
      UploadResult dead = {};
      dead.rgb565 = CAMERA_USE_RGB565;
      strlcpy(dead.detail, "camera not initialised", sizeof dead.detail);
      Serial.printf("ORDER %s refused: camera not initialised\n", o.requestId);
      ack(o.requestId, dead);
    } else {
      handleOrder(o);
    }
  }

  const uint32_t now = millis();
  if ((int32_t)(now - nextHeartbeatMs) >= 0) {
    nextHeartbeatMs = now + 30000;
    Serial.printf("[%5lus] idle | photos ok=%lu failed=%lu skipped=%lu | camera=%s | net=%s | free heap %u\n",
                  (unsigned long)(now / 1000), (unsigned long)okCount, (unsigned long)failCount,
                  (unsigned long)skippedCount, cameraReady() ? "ready" : "NOT READY", netStage(),
                  (unsigned)ESP.getFreeHeap());
  }
  delay(5);
}
