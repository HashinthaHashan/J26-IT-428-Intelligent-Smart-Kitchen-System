// MQ-3 / MQ-135 analog reading, ADC -> Rs -> ppm, and the DHT22.
// The conversion helpers are header-only and free of Arduino headers so they can
// be tested on a PC.
#pragma once

#include <math.h>
#include <stdint.h>

#include "config.h"

// ------------------------- conversion maths (pure) --------------------------

// Undo the divider: millivolts at the ESP32 pin -> millivolts at the sensor AO.
inline float mqAoMvFromPinMv(float pinMv) {
  return pinMv * (DIVIDER_R_TOP_OHM + DIVIDER_R_BOTTOM_OHM) / DIVIDER_R_BOTTOM_OHM;
}

// AO = Vcc * RL / (Rs + RL)  =>  Rs = RL * (Vcc - AO) / AO
inline float mqRsFromAoMv(float aoMv, float rlOhm) {
  if (aoMv < 1.0f) aoMv = 1.0f;
  if (aoMv > MQ_VCC_MV - 1.0f) aoMv = MQ_VCC_MV - 1.0f;  // keep Rs > 0
  return rlOhm * (MQ_VCC_MV - aoMv) / aoMv;
}

// concentration = scale * A * (Rs/R0)^B   (power-law fit; see config.h)
inline float mqPpm(float rsOhm, float r0Ohm, float a, float b, float scale) {
  if (rsOhm <= 0 || r0Ohm <= 0) return PPM_MIN;
  float ppm = scale * a * powf(rsOhm / r0Ohm, b);
  if (!(ppm >= PPM_MIN)) ppm = PPM_MIN;  // also catches NaN
  if (ppm > PPM_MAX) ppm = PPM_MAX;
  return ppm;
}

// ---------------------------- hardware access -------------------------------

struct MqReading {
  float pinMv;   // averaged mV at the ESP32 pin
  float aoMv;    // reconstructed sensor AO voltage
  float rsOhm;   // sensor resistance
  float ppm;     // converted with the configured R0
  bool valid;    // false = AO ~ 0 V: unpowered / wrong supply / disconnected
};

enum MqSensor { MQ_3 = 0, MQ_135 = 1 };

struct DhtReading {
  float tempC;
  float rhPct;
  bool ok;  // false = this call failed (value is the last good one, if any)
  bool everGood;  // false until the first successful read
};

void sensorsBegin();
MqReading sensorsReadMq(MqSensor which);
const char *mqName(MqSensor which);
DhtReading sensorsReadDht();

// Returns the number of failed checks (0 = good).
int sensorsSelfTest();
