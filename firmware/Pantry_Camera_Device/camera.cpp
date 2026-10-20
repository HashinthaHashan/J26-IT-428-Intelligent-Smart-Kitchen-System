#include "camera.h"

#include <Arduino.h>
#include <esp_camera.h>
#include <img_converters.h>

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

bool cameraBegin() {
  if (!psramFound()) {
    Serial.println(F("[CAM] PSRAM not found. Select the board 'AI Thinker ESP32-CAM' (PSRAM enabled) "
                     "in Tools > Board; without PSRAM the frame buffers do not fit."));
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
                       "config.h."));
    }
    return false;
  }
  sensor_t *s = esp_camera_sensor_get();
  if (s) {
    Serial.printf("[CAM] sensor detected: PID 0x%04x (0x2642 = OV2640) | format %s | %dx%d\n",
                  (unsigned)s->id.PID, CAMERA_USE_RGB565 ? "RGB565" : "JPEG", CAMERA_FRAME_W,
                  CAMERA_FRAME_H);
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

// Returns an RGB565 view of the frame. *owned is set when the caller must free it.
static const uint8_t *toRgb565(camera_fb_t *fb, uint8_t **owned) {
  *owned = nullptr;
  if (fb->format == PIXFORMAT_RGB565) return fb->buf;
  if (fb->format == PIXFORMAT_JPEG) {
    if (fb->len < 4 || fb->buf[0] != 0xFF || fb->buf[1] != 0xD8) {
      Serial.println(F("[CAM] frame is not a valid JPEG (no FFD8 header). RHYX-M21-45? set "
                       "CAMERA_USE_RGB565 true."));
      return nullptr;
    }
    uint8_t *buf = (uint8_t *)ps_malloc((size_t)fb->width * fb->height * 2);
    if (!buf) {
      Serial.println(F("[CAM] out of memory for the RGB565 buffer."));
      return nullptr;
    }
    if (!jpg2rgb565(fb->buf, fb->len, buf, JPG_SCALE_NONE)) {
      Serial.println(F("[CAM] JPEG decode failed."));
      free(buf);
      return nullptr;
    }
    *owned = buf;
    return buf;
  }
  Serial.printf("[CAM] unsupported pixel format %d\n", (int)fb->format);
  return nullptr;
}

MeasureResult cameraMeasure() {
  MeasureResult r = {};
  r.split = ROI_SPLIT;
  if (!ready) return r;

  // Let auto-exposure / white balance settle, then take the real frame.
  for (int i = 0; i < WARMUP_FRAMES; i++) {
    camera_fb_t *warm = esp_camera_fb_get();
    if (warm) esp_camera_fb_return(warm);
    delay(120);
  }
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) {
    Serial.println(F("[CAM] capture failed (no frame)."));
    return r;
  }
  r.width = fb->width;
  r.height = fb->height;
  r.frameBytes = fb->len;

  uint8_t *owned = nullptr;
  const uint8_t *px = toRgb565(fb, &owned);
  if (px) {
    if (ROI_SPLIT) {
      const RegionPx b = regionFromFractions(ROI_BANANA_X, ROI_BANANA_Y, ROI_BANANA_W, ROI_BANANA_H,
                                             r.width, r.height);
      const RegionPx p = regionFromFractions(ROI_POTATO_X, ROI_POTATO_Y, ROI_POTATO_W, ROI_POTATO_H,
                                             r.width, r.height);
      r.banana = computeFeatures(px, r.width, r.height, b, CAMERA_RGB565_BIG_ENDIAN);
      r.potato = computeFeatures(px, r.width, r.height, p, CAMERA_RGB565_BIG_ENDIAN);
    } else {
      const RegionPx all = {0, 0, r.width, r.height};
      r.banana = computeFeatures(px, r.width, r.height, all, CAMERA_RGB565_BIG_ENDIAN);
      r.potato = r.banana;  // combined mode: one measurement reported for both items
    }
    r.ok = true;
  }
  if (owned) free(owned);
  esp_camera_fb_return(fb);
  return r;
}

struct SnapshotHandle {
  camera_fb_t *fb;
  uint8_t *encoded;
};

bool cameraSnapshotJpeg(uint8_t **data, size_t *len, void **handle) {
  if (!ready) return false;
  camera_fb_t *fb = esp_camera_fb_get();
  if (!fb) return false;
  SnapshotHandle *h = (SnapshotHandle *)malloc(sizeof(SnapshotHandle));
  if (!h) {
    esp_camera_fb_return(fb);
    return false;
  }
  h->fb = fb;
  h->encoded = nullptr;
  if (fb->format == PIXFORMAT_JPEG) {
    *data = fb->buf;
    *len = fb->len;
  } else {
    size_t outLen = 0;
    if (!frame2jpg(fb, 80, &h->encoded, &outLen)) {
      esp_camera_fb_return(fb);
      free(h);
      return false;
    }
    *data = h->encoded;
    *len = outLen;
  }
  *handle = h;
  return true;
}

void cameraReleaseJpeg(void *handle) {
  SnapshotHandle *h = (SnapshotHandle *)handle;
  if (!h) return;
  if (h->encoded) free(h->encoded);
  if (h->fb) esp_camera_fb_return(h->fb);
  free(h);
}
