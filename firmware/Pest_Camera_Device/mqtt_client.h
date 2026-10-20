// WiFi + MQTT on a dedicated FreeRTOS task (core 0), the same proven pattern as the
// other boards. The camera board only RECEIVES capture orders and REPORTS back; the
// photo itself goes over HTTP (see camera.cpp).
#pragma once

#include <stdint.h>

// A photo request relayed by the backend (the sensor board cannot reach this board).
struct CaptureOrder {
  char requestId[24];
  uint32_t receivedMs;  // millis() when it arrived (stale orders are dropped)
};

// The acknowledgement published after every capture attempt.
struct DoneMsg {
  char requestId[24];
  bool uploadOk;
  bool rgb565;
  uint32_t bytes;
  char detail[56];
};

void netBegin();
bool netIsOnline();      // WiFi AND MQTT up
const char *netStage();  // "ONLINE" | "OFFLINE(mqtt)" | "OFFLINE(wifi)"
uint32_t netEpochNow();  // UTC seconds, or 0 before the first NTP sync

bool netPollOrder(CaptureOrder &out);
// Queued for the network task; if MQTT is down the ack is dropped (no local queue
// is kept for photos: a missed capture just means that trial gets no species).
void netPublishDone(const DoneMsg &d);
