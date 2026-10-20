#include "sensors.h"

#include <Arduino.h>
#include <DHT.h>

static DHT dht(PIN_DHT, DHT22);
static float lastTemp = 0.0f;
static float lastRh = 0.0f;
static bool everGood = false;

void sensorsBegin() {
  analogSetPinAttenuation(PIN_MQ3_AO, ADC_11db);
  analogSetPinAttenuation(PIN_MQ135_AO, ADC_11db);
  pinMode(PIN_MQ3_AO, INPUT);
  pinMode(PIN_MQ135_AO, INPUT);
  dht.begin();
}

const char *mqName(MqSensor which) { return which == MQ_3 ? "MQ-3 ethanol" : "MQ-135 ammonia"; }

MqReading sensorsReadMq(MqSensor which) {
  const int pin = which == MQ_3 ? PIN_MQ3_AO : PIN_MQ135_AO;
  const float rl = which == MQ_3 ? MQ3_RL_OHM : MQ135_RL_OHM;
  const float r0 = which == MQ_3 ? MQ3_R0_OHM : MQ135_R0_OHM;

  // analogReadMilliVolts() applies the ESP32's factory ADC calibration.
  uint32_t sum = 0;
  for (int i = 0; i < MQ_ADC_SAMPLES; i++) {
    sum += analogReadMilliVolts(pin);
    delayMicroseconds(200);
  }
  MqReading r;
  r.pinMv = (float)sum / MQ_ADC_SAMPLES;
  r.aoMv = mqAoMvFromPinMv(r.pinMv);
  r.valid = r.aoMv >= MQ_MIN_VALID_MV;
  r.rsOhm = mqRsFromAoMv(r.aoMv, rl);
  if (!r.valid) {
    r.ppm = PPM_MIN;
  } else if (which == MQ_3) {
    r.ppm = mqPpm(r.rsOhm, r0, MQ3_CURVE_A_MGL, MQ3_CURVE_B, MQ3_MGL_TO_PPM);
  } else {
    r.ppm = mqPpm(r.rsOhm, r0, MQ135_CURVE_A, MQ135_CURVE_B, 1.0f);
  }
  return r;
}

DhtReading sensorsReadDht() {
  const float t = dht.readTemperature();
  const float h = dht.readHumidity();
  DhtReading r;
  if (isnan(t) || isnan(h)) {
    r.ok = false;
  } else {
    lastTemp = t;
    lastRh = h;
    everGood = true;
    r.ok = true;
  }
  r.tempC = lastTemp;
  r.rhPct = lastRh;
  r.everGood = everGood;
  return r;
}

int sensorsSelfTest() {
  // Reference values computed in Python from the same formulas:
  //   MQ-3   scale*0.3934*ratio^-1.504*530.7 : ratio 60 -> 0.442, 1 -> 208.777, 1.88 -> 80.79
  //   MQ-135 102.2*ratio^-2.473              : ratio 3.6 -> 4.302, 1 -> 102.2
  int fails = 0;
  auto approx = [](float a, float b) { return fabsf(a - b) <= 0.01f * fabsf(b) + 0.01f; };
  const float r0 = 10000.0f;
  fails += !approx(mqPpm(60 * r0, r0, MQ3_CURVE_A_MGL, MQ3_CURVE_B, MQ3_MGL_TO_PPM), 0.442f);
  fails += !approx(mqPpm(1 * r0, r0, MQ3_CURVE_A_MGL, MQ3_CURVE_B, MQ3_MGL_TO_PPM), 208.777f);
  fails += !approx(mqPpm(1.88f * r0, r0, MQ3_CURVE_A_MGL, MQ3_CURVE_B, MQ3_MGL_TO_PPM), 80.79f);
  fails += !approx(mqPpm(3.6f * r0, r0, MQ135_CURVE_A, MQ135_CURVE_B, 1.0f), 4.302f);
  fails += !approx(mqPpm(1 * r0, r0, MQ135_CURVE_A, MQ135_CURVE_B, 1.0f), 102.2f);
  // AO = Vcc/2  =>  Rs == RL
  fails += !approx(mqRsFromAoMv(MQ_VCC_MV / 2.0f, 5000.0f), 5000.0f);
  // Divider: 10k/15k => x2.5/1.5 ... AO = pin * (10k+15k)/15k
  fails += !approx(mqAoMvFromPinMv(1500.0f), 1500.0f * (DIVIDER_R_TOP_OHM + DIVIDER_R_BOTTOM_OHM) / DIVIDER_R_BOTTOM_OHM);
  return fails;
}
