#include "sensors.h"

#include <Arduino.h>

static Debouncer debouncers[SRC_COUNT];

void sensorsBegin() {
  pinMode(PIN_PIR, INPUT);
  pinMode(PIN_IR, INPUT);
  pinMode(PIN_VIB, INPUT);
}

void sensorsRawLevels(int &pir, int &ir, int &vib) {
  pir = digitalRead(PIN_PIR);
  ir = digitalRead(PIN_IR);
  vib = digitalRead(PIN_VIB);
}

SensorLevels sensorsRead() {
  SensorLevels l;
  l.pir = (digitalRead(PIN_PIR) == HIGH) == PIR_ACTIVE_HIGH;
  l.ir = (digitalRead(PIN_IR) == HIGH) == IR_ACTIVE_HIGH;
  l.vib = (digitalRead(PIN_VIB) == HIGH) == VIB_ACTIVE_HIGH;
  return l;
}

uint8_t sensorsPoll(uint32_t nowMs) {
  const SensorLevels l = sensorsRead();
  // The PIR is meaningless until its element has stabilised after power-up.
  const bool pirReady = nowMs >= (uint32_t)PIR_WARMUP_S * 1000UL;
  uint8_t fired = 0;
  if (debouncers[SRC_PIR].update(l.pir && pirReady, nowMs, DEBOUNCE_MS, COOLDOWN_MS)) fired |= 1 << SRC_PIR;
  if (debouncers[SRC_IR].update(l.ir, nowMs, DEBOUNCE_MS, COOLDOWN_MS)) fired |= 1 << SRC_IR;
  if (debouncers[SRC_VIB].update(l.vib, nowMs, DEBOUNCE_MS, COOLDOWN_MS)) fired |= 1 << SRC_VIB;
  return fired;
}

int sensorsSelfTest() {
  int fails = 0;
  Debouncer d;
  // A 100 ms blip is not a trigger.
  fails += d.update(true, 1000, 200, 8000);
  fails += d.update(true, 1100, 200, 8000);
  fails += d.update(false, 1150, 200, 8000);
  // 200 ms of steady activity fires exactly once...
  fails += d.update(true, 2000, 200, 8000);
  fails += d.update(true, 2100, 200, 8000);
  fails += !d.update(true, 2200, 200, 8000);
  // ...and a stuck-active input does not fire again.
  fails += d.update(true, 3000, 200, 8000);
  fails += d.update(true, 20000, 200, 8000);
  // After going inactive and active again, the 8 s cooldown still holds...
  fails += d.update(false, 2300, 200, 8000);
  fails += d.update(true, 4000, 200, 8000);
  fails += d.update(true, 4300, 200, 8000);
  fails += d.update(false, 4400, 200, 8000);
  // ...and fires again once the cooldown has passed (2200 + 8000 = 10200).
  fails += d.update(true, 10300, 200, 8000);
  fails += !d.update(true, 10500, 200, 8000);
  return fails;
}
