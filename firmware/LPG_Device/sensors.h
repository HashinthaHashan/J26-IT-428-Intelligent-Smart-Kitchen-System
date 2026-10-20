// MQ-2 (analog) and DHT22 reading plus the ADC -> Rs -> ppm conversion.
// The conversion helpers are header-only and free of Arduino headers so they can
// be tested on a PC.
#pragma once

#include <math.h>
#include <stdint.h>

#include "config.h"

// ------------------------- conversion maths (pure) --------------------------

// Undo the GPIO34 voltage divider: millivolts at the pin -> millivolts at AO.
inline float mq2AoMvFromPinMv(float pinMv) {
  return pinMv * (DIVIDER_R_TOP_OHM + DIVIDER_R_BOTTOM_OHM) / DIVIDER_R_BOTTOM_OHM;
}

// AO = Vcc * RL / (Rs + RL)  =>  Rs = RL * (Vcc - AO) / AO
inline float mq2RsFromAoMv(float aoMv) {
  if (aoMv < 1.0f) aoMv = 1.0f;
  if (aoMv > MQ2_VCC_MV - 1.0f) aoMv = MQ2_VCC_MV - 1.0f;  // keep Rs > 0
  return MQ2_RL_OHM * (MQ2_VCC_MV - aoMv) / aoMv;
}

// log10(Rs/R0) = A - B*log10(ppm)  =>  ppm = 10 ^ ((A - log10(Rs/R0)) / B)
inline float mq2PpmFromRs(float rsOhm, float r0Ohm) {
  if (rsOhm <= 0 || r0Ohm <= 0) return PPM_MIN;
  const float ratio = rsOhm / r0Ohm;
  float ppm = powf(10.0f, (MQ2_CURVE_A - log10f(ratio)) / MQ2_CURVE_B);
  if (!(ppm >= PPM_MIN)) ppm = PPM_MIN;  // also catches NaN
  if (ppm > PPM_MAX) ppm = PPM_MAX;
  return ppm;
}

// ---------------------------- hardware access -------------------------------

struct Mq2Reading {
  float pinMv;   // averaged millivolts measured at the ESP32 pin
  float aoMv;    // reconstructed sensor AO voltage
  float rsOhm;   // sensor resistance
  float ppm;     // converted with MQ2_R0_OHM
  bool valid;    // false = AO ~ 0 V: sensor unpowered / disconnected
};

struct DhtReading {
  float tempC;
  float rhPct;
  bool fresh;  // false if this call failed and the last good value was reused
};

void sensorsBegin();
Mq2Reading sensorsReadMq2();
// DHT22 only refreshes every 2 s; the Adafruit library returns its cached value
// in between, so calling this at 1 Hz is safe.
DhtReading sensorsReadDht();

// Returns the number of failed checks (0 = good). Expected values computed
// independently in Python from the same formulas.
int sensorsSelfTest();
