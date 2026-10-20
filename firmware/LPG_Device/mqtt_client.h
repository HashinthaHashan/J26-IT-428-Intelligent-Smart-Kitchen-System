// WiFi + MQTT on a dedicated FreeRTOS task (core 0).
//
// Why a separate task: connecting to an unreachable WiFi/broker blocks for
// seconds. Sensing, the safety override and actuation run in loop() on core 1
// and never wait on the network - this is the "edge failsafe" requirement.
// The two sides only talk through two small queues.
#pragma once

#include <stdint.h>

struct TelemetrySample {
  uint32_t seq;
  uint32_t epoch;  // UTC seconds when sampled; 0 = clock was not synced yet
  uint32_t ms;     // millis() when sampled (used to back-date if epoch == 0)
  float ppm;
  float tempC;
  float rhPct;
  float windowFrac;
  uint8_t tier;    // Tier enum
  bool fanOn;
  bool offline;    // edge_offline_mode: network was down when this was sampled
};

struct ManualCommand {
  char action[10];  // "fan" | "window"
  char source[12];  // "manual" | "auto" | "override"
  float value;
};

// Creates the queues and starts the network task.
void netBegin();

// True only while WiFi AND the MQTT session are up.
bool netIsOnline();

// "ONLINE", "OFFLINE(mqtt)" (WiFi up, broker not) or "OFFLINE(wifi)": which
// stage is failing, shown in the per-second Serial line.
const char *netStage();

// Queue a sample for publishing. If the queue is full the OLDEST sample is
// dropped (newest data matters most). Never blocks.
void netEnqueueTelemetry(const TelemetrySample &s);

// Fetch the next received command, if any (non-blocking).
bool netPollCommand(ManualCommand &out);

// UTC seconds from the system clock, or 0 if NTP has not synced yet. The clock
// keeps counting on its own after the last sync, so timestamps stay correct
// while offline.
uint32_t netEpochNow();
