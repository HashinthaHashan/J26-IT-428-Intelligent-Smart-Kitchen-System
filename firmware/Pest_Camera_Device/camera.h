// ESP32-CAM (AI-Thinker pinout): capture one photo on request and POST it to the
// backend. The camera is initialised once at boot and then left idle: it only
// captures when a request arrives.
#pragma once

#include <stddef.h>
#include <stdint.h>

struct UploadResult {
  bool captured;       // a frame was grabbed
  bool uploadOk;       // the backend answered HTTP 200
  int httpCode;        // <0 = could not connect/send
  size_t bytes;        // size of the image sent
  bool rgb565;         // true = uncompressed RGB565 (RHYX path)
  uint32_t captureMs;  // time spent grabbing the frame
  uint32_t uploadMs;   // time spent sending it
  char detail[56];     // short human-readable reason on failure
  char label[24];      // backend's classification (from its JSON reply), if any
};

bool cameraBegin();
bool cameraReinit();
bool cameraReady();

// Captures one photo and uploads it with the given request id. Never blocks the
// network task (MQTT keeps running on the other core).
UploadResult cameraCaptureAndUpload(const char *requestId);
