#include "sensors.h"

#include <Arduino.h>
#include <DHT.h>

static DHT dht(PIN_DHT, DHT22);
static float lastTemp = 25.0f;  // used until the first good DHT read
static float lastRh = 50.0f;

void sensorsBegin() {
  analogSetPinAttenuation(PIN_MQ2_AO, ADC_11db);  // ~0-3.1 V input range
  pinMode(PIN_MQ2_AO, INPUT);
  dht.begin();
}

Mq2Reading sensorsReadMq2() {
  // analogReadMilliVolts() applies the ESP32's factory ADC calibration, which
  // matters: the raw 0-4095 count is noticeably non-linear on this chip.
  uint32_t sum = 0;
  for (int i = 0; i < MQ2_ADC_SAMPLES; i++) {
    sum += analogReadMilliVolts(PIN_MQ2_AO);
    delayMicroseconds(200);
  }
  Mq2Reading r;
  r.pinMv = (float)sum / MQ2_ADC_SAMPLES;
  r.aoMv = mq2AoMvFromPinMv(r.pinMv);
  r.valid = r.aoMv >= MQ2_MIN_VALID_MV;
  r.rsOhm = mq2RsFromAoMv(r.aoMv);
  r.ppm = r.valid ? mq2PpmFromRs(r.rsOhm, MQ2_R0_OHM) : PPM_MIN;
  return r;
}

DhtReading sensorsReadDht() {
  const float t = dht.readTemperature();
  const float h = dht.readHumidity();
  DhtReading r;
  if (isnan(t) || isnan(h)) {
    r.fresh = false;
  } else {
    lastTemp = t;
    lastRh = h;
    r.fresh = true;
  }
  r.tempC = lastTemp;
  r.rhPct = lastRh;
  return r;
}

int sensorsSelfTest() {
  // Reference values from Python: 10**((1.27 - log10(ratio)) / 0.46)
  //   ratio 9.8 -> 4.04 ppm, 1.0 -> 576.59, 0.5 -> 2601.85
  int fails = 0;
  auto near = [](float a, float b, float relTol) {
    return fabsf(a - b) <= relTol * fabsf(b) + 0.01f;
  };
  const float r0 = 10000.0f;
  fails += !near(mq2PpmFromRs(9.8f * r0, r0), 4.04f, 0.01f);
  fails += !near(mq2PpmFromRs(1.0f * r0, r0), 576.59f, 0.01f);
  fails += !near(mq2PpmFromRs(0.5f * r0, r0), 2601.85f, 0.01f);
  // Rs from AO: AO = Vcc/2 means Rs == RL
  fails += !near(mq2RsFromAoMv(MQ2_VCC_MV / 2.0f), MQ2_RL_OHM, 0.001f);
  // Divider round trip
  const float ratio = (DIVIDER_R_TOP_OHM + DIVIDER_R_BOTTOM_OHM) / DIVIDER_R_BOTTOM_OHM;
  fails += !near(mq2AoMvFromPinMv(1000.0f), 1000.0f * ratio, 0.001f);
  return fails;
}
