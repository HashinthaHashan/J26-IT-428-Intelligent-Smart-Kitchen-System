// ESP32-CAM (AI-Thinker pinout) capture + on-device colour feature extraction.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "color_features.h"

struct MeasureResult {
  bool ok;              // false = capture/decode failed (see Serial)
  int width, height;
  bool split;           // true = two regions (banana left, potato right); false = one combined
  ColorFeatures banana; // in combined mode the same measurement is stored in both
  ColorFeatures potato;
  size_t frameBytes;    // JPEG size, or raw RGB565 size
};

// Initialises the camera. Returns false (and says why) on failure, e.g. no PSRAM
// or a sensor variant the chosen pixel format does not support.
bool cameraBegin();

// Releases and re-initialises the camera after repeated failures.
bool cameraReinit();

// Discards warm-up frames, captures one, measures the region(s). Never throws; a
// failure is reported through result.ok == false.
MeasureResult cameraMeasure();

// A JPEG for the setup web page. Caller must call cameraReleaseJpeg(). Returns
// false on failure.
bool cameraSnapshotJpeg(uint8_t **data, size_t *len, void **handle);
void cameraReleaseJpeg(void *handle);
