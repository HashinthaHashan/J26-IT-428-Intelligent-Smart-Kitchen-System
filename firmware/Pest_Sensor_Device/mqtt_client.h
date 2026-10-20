// WiFi + MQTT on a dedicated FreeRTOS task (core 0), the same proven pattern as the
// LPG and pantry boards. A failed connect never stalls sensing or the deterrent.
//
// Three kinds of outgoing message:
//   OUT_EVENT      PestEvent, queued while offline (~2 h) and back-dated on flush
//   OUT_TRIAL      DeterrenceTrial, queued the same way
//   capture request  published IMMEDIATELY or not at all (a photo request that is
//                    minutes old is useless), through its own small queue
#pragma once

#include <stdint.h>

enum OutKind : uint8_t { OUT_EVENT = 0, OUT_TRIAL = 1 };

struct OutRec {
  OutKind kind;
  uint32_t epoch;  // UTC seconds when it happened; 0 = clock was not synced yet
  uint32_t ms;     // millis() then (used to back-date if epoch == 0)

  // OUT_EVENT
  char trigger[12];  // "PIR" | "IR" | "Vibration"
  char zone[20];
  bool pir;          // PIR level at the moment of the trigger
  bool vibTrigger;
  float vibRmsG;     // PLACEHOLDER: the sensor is digital, so 0.0 or 1.0
  bool cameraAsked;  // a capture request was sent for this event

  // OUT_TRIAL
  char trialId[40];
  char species[12];  // "" = unknown
  char condition[16];
  uint16_t activationS, observationS;
};

// A command from the backend (or a manual test) addressed to this device.
struct DeviceCommand {
  char action[16];     // "deterrent" (manual test) | "classification" (species answer)
  char source[12];     // "manual" | "auto" | "override"
  char condition[16];  // params.condition (manual test only): control|vibration_only|led_only|vibration_led
  char species[12];    // params.species ("rat" | "cockroach" | "non_pest" | "")
  char requestId[24];  // params.request_id: which capture request this answers
  float confidence;
};

void netBegin();
bool netIsOnline();        // WiFi AND MQTT up
const char *netStage();    // "ONLINE" | "OFFLINE(mqtt)" | "OFFLINE(wifi)"
uint32_t netEpochNow();    // UTC seconds, or 0 before the first NTP sync

void netEnqueue(const OutRec &rec);  // drops the oldest if full
uint32_t netQueued();                // events/trials waiting to be sent

// Asks the backend to have the camera take a photo. Returns false (nothing sent)
// when offline or the clock is not synced (the trial still starts, it just gets no species).
bool netSendCaptureRequest(const char *requestId, const char *trigger, const char *zone,
                           uint32_t eventEpoch);

bool netPollCommand(DeviceCommand &out);
