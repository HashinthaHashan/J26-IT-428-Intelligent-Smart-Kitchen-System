#include "camera.h"

#include <Arduino.h>
#include <HTTPClient.h>
#include <WiFi.h>
#include <esp_camera.h>

#include "config.h"

// AI-Thinker ESP32-CAM pinout.
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22

static bool ready = false;

bool cameraReady() { return ready; }

bool cameraBegin() {
  if (!psramFound()) {
    Serial.println(F("[CAM] PSRAM not found. Select the board 'AI Thinker ESP32-CAM' (PSRAM enabled) "
                     "in Tools > Board; without PSRAM the frame buffer does not fit."));
    return false;
  }
  camera_config_t c = {};
  c.ledc_channel = LEDC_CHANNEL_0;
  c.ledc_timer = LEDC_TIMER_0;
  c.pin_d0 = Y2_GPIO_NUM;
  c.pin_d1 = Y3_GPIO_NUM;
  c.pin_d2 = Y4_GPIO_NUM;
  c.pin_d3 = Y5_GPIO_NUM;
  c.pin_d4 = Y6_GPIO_NUM;
  c.pin_d5 = Y7_GPIO_NUM;
  c.pin_d6 = Y8_GPIO_NUM;
  c.pin_d7 = Y9_GPIO_NUM;
  c.pin_xclk = XCLK_GPIO_NUM;
  c.pin_pclk = PCLK_GPIO_NUM;
  c.pin_vsync = VSYNC_GPIO_NUM;
  c.pin_href = HREF_GPIO_NUM;
  c.pin_sccb_sda = SIOD_GPIO_NUM;
  c.pin_sccb_scl = SIOC_GPIO_NUM;
  c.pin_pwdn = PWDN_GPIO_NUM;
  c.pin_reset = RESET_GPIO_NUM;
  c.xclk_freq_hz = 20000000;
  c.pixel_format = CAMERA_USE_RGB565 ? PIXFORMAT_RGB565 : PIXFORMAT_JPEG;
  c.frame_size = CAMERA_FRAMESIZE;
  c.jpeg_quality = CAMERA_JPEG_QUALITY;
  c.fb_count = 1;
  c.fb_location = CAMERA_FB_IN_PSRAM;
  c.grab_mode = CAMERA_GRAB_LATEST;

  const esp_err_t err = esp_camera_init(&c);
  if (err != ESP_OK) {
    Serial.printf("[CAM] camera init FAILED (0x%x). Check the ribbon cable is seated and the board is "
                  "powered from a solid 5 V.\n", (unsigned)err);
    if (!CAMERA_USE_RGB565) {
      Serial.println(F("[CAM] If your module is the RHYX-M21-45 (not OV2640), set CAMERA_USE_RGB565 true in "
                       "config.h (RGB565 + QVGA, uploaded uncompressed)."));
    }
    return false;
  }
  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    Serial.printf("[CAM] sensor detected: PID 0x%04x (0x2642 = OV2640) | format %s | frame size id %d\n",
                  (unsigned)s->id.PID, CAMERA_USE_RGB565 ? "RGB565" : "JPEG", (int)CAMERA_FRAMESIZE);
    if (s->id.PID != 0x2642) {
      Serial.println(F("[CAM] NOTE: this is not an OV2640. If captures fail with JPEG, set "
                       "CAMERA_USE_RGB565 true (RHYX-M21-45 path)."));
    }
  }
  ready = true;
  return true;
}

bool cameraReinit() {
  if (ready) {
    esp_camera_deinit();
    ready = false;
  }
  delay(200);
  return cameraBegin();
}

UploadResult cameraCaptureAndUpload(const char *requestId) {
  UploadResult r = {};
  r.rgb565 = CAMERA_USE_RGB565;
  r.httpCode = -1;
  if (!ready) {
    strlcpy(r.detail, "camera not initialised", sizeof r.detail);
    return r;
  }
  if (WiFi.status() != WL_CONNECTED) {
    strlcpy(r.detail, "WiFi is down: capture skipped", sizeof r.detail);
    Serial.println(F("[CAM] WiFi is down: this capture is skipped (the sensor board's trial still runs, it just gets no species)."));
    return r;
  }

  const uint32_t t0 = millis();
  if (USE_FLASH_LED) {
    digitalWrite(PIN_FLASH_LED, HIGH);
    delay(80);
  }
  for (int i = 0; i < WARMUP_FRAMES; i++) {
    camera_fb_t *warm = esp_camera_fb_get();
    if (warm) esp_camera_fb_return(warm);
  }
  camera_fb_t *fb = esp_camera_fb_get();
  if (USE_FLASH_LED) digitalWrite(PIN_FLASH_LED, LOW);
  r.captureMs = millis() - t0;
  if (!fb) {
    strlcpy(r.detail, "capture failed (no frame)", sizeof r.detail);
    return r;
  }
  r.captured = true;
  r.bytes = fb->len;
  const bool isJpeg = fb->format == PIXFORMAT_JPEG;
  if (isJpeg && (fb->len < 4 || fb->buf[0] != 0xFF || fb->buf[1] != 0xD8)) {
    esp_camera_fb_return(fb);
    r.captured = false;
    strlcpy(r.detail, "frame is not a valid JPEG (RHYX-M21-45? set CAMERA_USE_RGB565 true)", sizeof r.detail);
    return r;
  }

  const uint32_t t1 = millis();
  WiFiClient client;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(HTTP_TIMEOUT_MS);
  char url[96];
  snprintf(url, sizeof url, "http://%s:%d%s", API_HOST, API_PORT, API_PHOTO_PATH);
  if (!http.begin(client, url)) {
    esp_camera_fb_return(fb);
    strlcpy(r.detail, "could not start the HTTP request", sizeof r.detail);
    return r;
  }
  http.addHeader("Content-Type", isJpeg ? "image/jpeg" : "application/octet-stream");
  http.addHeader("Authorization", "Bearer " API_TOKEN);
  http.addHeader("X-Request-Id", requestId);
  http.addHeader("X-Image-Format", isJpeg ? "jpeg" : "rgb565");
  if (!isJpeg) {
    http.addHeader("X-Image-Width", String(fb->width));
    http.addHeader("X-Image-Height", String(fb->height));
  }
  r.httpCode = http.POST(fb->buf, fb->len);
  r.uploadMs = millis() - t1;
  esp_camera_fb_return(fb);

  if (r.httpCode == 200) {
    r.uploadOk = true;
    const String body = http.getString();  // small JSON: {"label":"cockroach",...}
    const int k = body.indexOf("\"label\":\"");
    if (k >= 0) {
      const int start = k + 9, end = body.indexOf('"', start);
      if (end > start) strlcpy(r.label, body.substring(start, end).c_str(), sizeof r.label);
    }
  } else if (r.httpCode < 0) {
    snprintf(r.detail, sizeof r.detail, "HTTP failed: %s", HTTPClient::errorToString(r.httpCode).c_str());
  } else if (r.httpCode == 401 || r.httpCode == 403) {
    snprintf(r.detail, sizeof r.detail, "HTTP %d: wrong API_TOKEN", r.httpCode);
  } else {
    snprintf(r.detail, sizeof r.detail, "HTTP %d from the backend", r.httpCode);
  }
  http.end();
  return r;
}
