// =============================================================================
// KitchenGuard - Component 02: Smart Pantry, BOARD 2 (ESP32-CAM, camera only)
//
// Every CAPTURE_INTERVAL_S (default 5 min) it takes one photo, computes simple
// colour features ON THE CHIP and publishes them (not the image) over MQTT:
//
//   topic  kitchenguard/pantry/pantry01/camera
//   items  banana + potato: hue_mean, brown_pct, green_pct, coverage_pct
//
// Why on-device: the ESP32-CAM has 4 MB of PSRAM, a 320x240 frame decodes in well
// under a second, and a ~300 byte message replaces a ~10 KB image. No image-upload
// endpoint is needed. A LAN-only setup web page (http://<board-ip>/) shows what the
// camera sees with the item regions drawn on it, so the camera can be aimed.
//
// This board has no sensors and shares no pins with the sensor board; the LED that
// lights the scene is driven by the SENSOR board (always on).
// =============================================================================

#include <Arduino.h>
#include <WebServer.h>
#include <WiFi.h>
#include <esp_system.h>

#include "camera.h"
#include "color_features.h"
#include "config.h"
#include "mqtt_client.h"

static WebServer web(80);
static bool webStarted = false;
static MeasureResult lastResult = {};
static uint32_t lastCaptureMs = 0;
static uint32_t captureCount = 0;
static uint32_t nextCaptureMs = 0;
static int consecutiveFailures = 0;

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

static void printItem(const char *name, const ColorFeatures &f) {
  if (!f.valid) {
    Serial.printf("  %-6s: nothing measurable (item coverage %.1f%% < %.1f%%)\n", name, f.coveragePct,
                  ITEM_MIN_COVERAGE_PCT);
    return;
  }
  Serial.printf("  %-6s: hue=%5.1f deg  brown=%5.1f%%  green=%5.1f%%  item coverage=%5.1f%%\n", name,
                f.hueMean, f.brownPct, f.greenPct, f.coveragePct);
}

// ---------------------------------------------------------------------------
// Setup web page
// ---------------------------------------------------------------------------

static void sendRoiBox(String &html, const char *label, float x, float y, float w, float h,
                       const char *color) {
  char buf[220];
  snprintf(buf, sizeof buf,
           "<div style='position:absolute;left:%.1f%%;top:%.1f%%;width:%.1f%%;height:%.1f%%;"
           "border:3px solid %s;box-sizing:border-box'><span style='background:%s;color:#fff;"
           "padding:1px 6px;font:12px sans-serif'>%s</span></div>",
           x * 100, y * 100, w * 100, h * 100, color, color, label);
  html += buf;
}

static void handleRoot() {
  String html =
      "<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'>"
      "<title>Pantry camera setup</title><body style='font-family:sans-serif;margin:12px'>"
      "<h3>Pantry camera: setup view</h3>"
      "<p>Aim the camera so the <b>banana</b> sits in the orange box and the <b>potato</b> in the "
      "blue box (or everything in the frame in combined mode). Plain white/grey background, "
      "steady light. Refreshes every 5 s.</p>"
      "<div style='position:relative;display:inline-block'>"
      "<img id=cam src='/snapshot.jpg' style='display:block;width:100%;max-width:640px'>";
  if (ROI_SPLIT) {
    sendRoiBox(html, "banana", ROI_BANANA_X, ROI_BANANA_Y, ROI_BANANA_W, ROI_BANANA_H, "#e67e22");
    sendRoiBox(html, "potato", ROI_POTATO_X, ROI_POTATO_Y, ROI_POTATO_W, ROI_POTATO_H, "#2980b9");
  } else {
    sendRoiBox(html, "combined (whole frame)", 0, 0, 1, 1, "#27ae60");
  }
  html += "</div><p>Next automatic capture in about ";
  const uint32_t now = millis();
  html += String(now >= nextCaptureMs ? 0 : (nextCaptureMs - now) / 1000);
  html += " s. Captures so far: ";
  html += String(captureCount);
  html += ".</p><script>setInterval(()=>{document.getElementById('cam').src='/snapshot.jpg?'+Date.now()},5000)"
          "</script></body>";
  web.send(200, "text/html", html);
}

static void handleSnapshot() {
  uint8_t *data = nullptr;
  size_t len = 0;
  void *handle = nullptr;
  if (!cameraSnapshotJpeg(&data, &len, &handle)) {
    web.send(503, "text/plain", "camera capture failed");
    return;
  }
  web.sendHeader("Cache-Control", "no-store");
  web.setContentLength(len);
  web.send(200, "image/jpeg", "");
  web.sendContent((const char *)data, len);
  cameraReleaseJpeg(handle);
}

// ---------------------------------------------------------------------------
// Capture cycle
// ---------------------------------------------------------------------------

static void doCapture() {
  const uint32_t now = millis();
  MeasureResult r = cameraMeasure();
  if (!r.ok) {
    consecutiveFailures++;
    Serial.printf("[%5lus] CAPTURE FAILED (%d in a row)\n", (unsigned long)(now / 1000), consecutiveFailures);
    if (consecutiveFailures == 3) {
      Serial.println(F("[CAM] 3 failures in a row: re-initialising the camera."));
      cameraReinit();
    }
    if (consecutiveFailures >= 6) {
      Serial.println(F("[CAM] 6 failures in a row: restarting the board."));
      delay(200);
      ESP.restart();
    }
    return;
  }
  consecutiveFailures = 0;
  lastResult = r;
  lastCaptureMs = now;

  Serial.printf("[%5lus] CAPTURE #%lu  %dx%d  frame %u bytes  mode=%s  net=%s\n",
                (unsigned long)(now / 1000), (unsigned long)captureCount, r.width, r.height,
                (unsigned)r.frameBytes, r.split ? "split" : "combined", netStage());
  printItem("banana", r.banana);
  printItem("potato", r.potato);
  Serial.printf("  free heap %u, free PSRAM %u\n", (unsigned)ESP.getFreeHeap(), (unsigned)ESP.getFreePsram());

  CameraSample s{};
  s.epoch = netEpochNow();
  s.ms = now;
  s.width = r.width;
  s.height = r.height;
  s.split = r.split;
  s.banana = r.banana;
  s.potato = r.potato;
  netEnqueue(s);
  captureCount++;
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println(F("=== KitchenGuard pantry CAMERA board, device " DEVICE_ID " ==="));
  logResetReason();

  // GPIO4 is the AI-Thinker's very bright built-in flash LED: keep it off. The scene
  // is lit by the LED on the sensor board.
  pinMode(4, OUTPUT);
  digitalWrite(4, LOW);

#if RUN_SELFTEST
  Serial.printf("[SELFTEST] colour features=%s\n", colorFeaturesSelfTest() ? "FAIL" : "ok");
#endif

  Serial.printf("[HW] sensor path: %s %dx%d | capture every %d s | regions: %s | WiFi '%s' -> MQTT %s:%d\n",
                CAMERA_USE_RGB565 ? "RGB565 (RHYX-M21-45 mode)" : "JPEG (OV2640 mode)",
                CAMERA_FRAME_W, CAMERA_FRAME_H, CAPTURE_INTERVAL_S,
                ROI_SPLIT ? "split banana-left / potato-right" : "combined", WIFI_SSID, MQTT_HOST,
                MQTT_PORT);

  if (!cameraBegin()) {
    Serial.println(F("[CAM] Camera is NOT running. Capture is disabled; fix the cause above and reset."));
  }

  netBegin();  // network runs on its own task; capture below never waits for it
  nextCaptureMs = millis() + (uint32_t)FIRST_CAPTURE_DELAY_S * 1000UL;
}

void loop() {
  const uint32_t now = millis();

  if (ENABLE_SETUP_WEB) {
    if (!webStarted && netWifiUp()) {
      web.on("/", handleRoot);
      web.on("/snapshot.jpg", handleSnapshot);
      web.begin();
      webStarted = true;
      Serial.printf("[WEB] setup page: http://%s/   (live view with the item regions drawn on it)\n",
                    WiFi.localIP().toString().c_str());
    }
    if (webStarted) web.handleClient();
  }

  if ((int32_t)(now - nextCaptureMs) >= 0) {
    nextCaptureMs = now + (uint32_t)CAPTURE_INTERVAL_S * 1000UL;
    doCapture();
  }
  delay(5);
}
