// WiFi + MQTT on a dedicated FreeRTOS task (core 0), same proven pattern as the
// LPG firmware: a failed connect can stall the network task for seconds but never
// the sensing loop. The two sides only talk through a queue.
#pragma once

#include <stdint.h>

// One 60 s sensor cycle. Gas, temperature and humidity come from ONE shared
// airspace, so the same values are published for both compartments.
struct PantrySample {
  uint32_t epoch;  // UTC seconds when sampled; 0 = clock was not synced yet
  uint32_t ms;     // millis() when sampled (used to back-date if epoch == 0)
  float mq3Ppm;
  float mq135Ppm;
  float tempC;
  float rhPct;
};

// Creates the queue and starts the network task.
void netBegin();

// True only while WiFi AND the MQTT session are up.
bool netIsOnline();

// "ONLINE", "OFFLINE(mqtt)" (WiFi up, broker not) or "OFFLINE(wifi)".
const char *netStage();

// Queue a cycle for publishing. If the queue is full the OLDEST cycle is dropped.
void netEnqueue(const PantrySample &s);

// UTC seconds from the system clock, or 0 if NTP has not synced yet.
uint32_t netEpochNow();
