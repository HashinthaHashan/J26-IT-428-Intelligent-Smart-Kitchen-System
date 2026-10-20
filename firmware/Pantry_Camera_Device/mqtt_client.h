// WiFi + MQTT on a dedicated FreeRTOS task (core 0), same proven pattern as the
// LPG and pantry-sensor firmware. A failed connect never stalls the capture loop.
#pragma once

#include <stdint.h>

#include "color_features.h"

// One capture's result, queued for publishing.
struct CameraSample {
  uint32_t epoch;  // UTC seconds when captured; 0 = clock was not synced yet
  uint32_t ms;     // millis() when captured (used to back-date if epoch == 0)
  uint16_t width, height;
  bool split;      // true = banana/potato regions; false = one combined measurement
  ColorFeatures banana;
  ColorFeatures potato;
};

void netBegin();
bool netIsOnline();   // WiFi AND MQTT up
bool netWifiUp();     // WiFi only (the setup web page only needs this)
const char *netStage();
void netEnqueue(const CameraSample &s);  // drops the oldest if full
uint32_t netEpochNow();
