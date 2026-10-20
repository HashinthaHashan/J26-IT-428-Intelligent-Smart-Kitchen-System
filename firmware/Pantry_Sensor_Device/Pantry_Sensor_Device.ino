// =============================================================================
// KitchenGuard - Component 02: Smart Pantry, BOARD 1 (gas + climate sensors)
//
// ONE shared pantry box holds a banana and a potato in the SAME airspace, so the
// MQ-3 / MQ-135 / DHT22 readings cannot be separated per item. The same reading
// is therefore published twice per cycle, once as compartment "banana" and once
// as "potato". That is a deliberate shared-sensor duplication, not a bug.
//
//   sensors.*      MQ-3 + MQ-135 (analog, 5 V powered) and DHT22
//   mqtt_client.*  WiFi + MQTT on its own task with an offline queue
//
// No actuators here except an LED (camera lighting) that is simply ON while the
// device is armed. No safety override or debouncing is needed.
// =============================================================================

#include <Arduino.h>
#include <esp_system.h>

#include "config.h"
#include "display.h"
#include "mqtt_client.h"
#include "sensors.h"

// ---------------------------------------------------------------------------
// Calibration mode
// ---------------------------------------------------------------------------
#if CALIBRATE_MODE

static const int CAL_WINDOW = 60;
struct CalStats {
  float rs[CAL_WINDOW];
  int count = 0;
  int head = 0;
};
static CalStats cal[2];

static void calibrateOne(MqSensor which, float rl, float cleanRatio, const char *constantName) {
  const int pin = which == MQ_3 ? PIN_MQ3_AO : PIN_MQ135_AO;
  const int rawAdc = analogRead(pin);
  const MqReading r = sensorsReadMq(which);
  if (!r.valid) {
    Serial.printf("%-15s adc=%4d pin=%5.0fmV  FAULT: AO ~0 V. MQ sensors need 5 V on VCC "
                  "(NOT 3.3 V); check VCC, GND, RL and the divider.\n",
                  mqName(which), rawAdc, r.pinMv);
    return;
  }
  CalStats &c = cal[which];
  c.rs[c.head] = r.rsOhm;
  c.head = (c.head + 1) % CAL_WINDOW;
  if (c.count < CAL_WINDOW) c.count++;
  float mean = 0;
  for (int i = 0; i < c.count; i++) mean += c.rs[i];
  mean /= c.count;
  float var = 0;
  for (int i = 0; i < c.count; i++) var += (c.rs[i] - mean) * (c.rs[i] - mean);
  const float stab = c.count > 1 ? 100.0f * sqrtf(var / c.count) / mean : 100.0f;
  Serial.printf("%-15s adc=%4d pin=%5.0fmV AO=%5.0fmV Rs=%8.0f ohm Rs/RL=%6.3f stab(%2ds)=%5.2f%% %s"
                " | Suggested %s = %.0f\n",
                mqName(which), rawAdc, r.pinMv, r.aoMv, r.rsOhm, r.rsOhm / rl, c.count, stab,
                (c.count >= CAL_WINDOW && stab < 2.0f) ? "STABLE  " : "settling", constantName,
                mean / cleanRatio);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  sensorsBegin();
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, HIGH);
  Serial.println();
  Serial.println(F("=== KitchenGuard PANTRY SENSORS: CALIBRATION MODE ==="));
  Serial.println(F("Clean air, 48 h burn-in done, sensors warm >= 10 min. Both sensors are printed"));
  Serial.println(F("separately. When a line says STABLE for a few minutes copy ITS suggested R0 into"));
  Serial.println(F("config.h (MQ3_R0_OHM and MQ135_R0_OHM), then set CALIBRATE_MODE false."));
  Serial.println(F("MQ VCC must be on the ESP32 5V/VIN pin, not 3.3 V."));
}

void loop() {
  static uint32_t next = 0;
  const uint32_t now = millis();
  if ((int32_t)(now - next) < 0) return;
  next = now + 1000;
  calibrateOne(MQ_3, MQ3_RL_OHM, MQ3_CLEAN_AIR_RATIO, "MQ3_R0_OHM");
  calibrateOne(MQ_135, MQ135_RL_OHM, MQ135_CLEAN_AIR_RATIO, "MQ135_R0_OHM");
  Serial.println();
}

// ---------------------------------------------------------------------------
// Normal operation
// ---------------------------------------------------------------------------
#else

static uint32_t nextLiveMs = 0;
static uint32_t nextPublishMs = 0;
static uint32_t cycle = 0;

static void logResetReason() {
  const esp_reset_reason_t r = esp_reset_reason();
  const char *name = "UNKNOWN";
  switch (r) {
    case ESP_RST_POWERON: name = "POWER-ON (normal cold start)"; break;
    case ESP_RST_SW: name = "software restart"; break;
    case ESP_RST_PANIC: name = "PANIC (crash)"; break;
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT: name = "WATCHDOG (a task hung)"; break;
    case ESP_RST_BROWNOUT: name = "BROWNOUT (power rail dropped!)"; break;
    default: break;
  }
  Serial.printf("[BOOT] reset reason: %s\n", name);
}

// Reads everything once. Returns false (and says why) if a reading is unusable,
// so bogus values are never published.
static bool readAll(PantrySample &out, bool verbose) {
  const MqReading m3 = sensorsReadMq(MQ_3);
  const MqReading m135 = sensorsReadMq(MQ_135);
  const DhtReading d = sensorsReadDht();

  if (!m3.valid || !m135.valid) {
    Serial.printf("[SENSOR FAULT] %s%s%sAO ~0 V. MQ sensors need 5 V on VCC (NOT 3.3 V) - check VCC, "
                  "GND, RL and the divider. Nothing published.\n",
                  m3.valid ? "" : "MQ-3 ", m135.valid ? "" : "MQ-135 ", "");
    return false;
  }
  if (!d.everGood) {
    Serial.println(F("[SENSOR FAULT] DHT22 has never returned a valid reading (check GPIO4 wiring "
                     "and its 10k pull-up). Nothing published."));
    return false;
  }
  if (!d.ok && verbose) {
    Serial.println(F("[WARN] DHT22 read failed this time; using the last good value."));
  }
  out.epoch = netEpochNow();
  out.ms = millis();
  out.mq3Ppm = m3.ppm;
  out.mq135Ppm = m135.ppm;
  out.tempC = d.tempC;
  out.rhPct = d.rhPct;
  return true;
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println(F("=== KitchenGuard pantry SENSOR board, device " DEVICE_ID " ==="));
  logResetReason();

  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, HIGH);  // camera lighting: simply ON while armed
  displayBegin();  // splash only; display-only, never gates sensing or networking
  sensorsBegin();

#if RUN_SELFTEST
  Serial.printf("[SELFTEST] sensor maths=%s\n", sensorsSelfTest() ? "FAIL" : "ok");
#endif

  if (MQ3_R0_OHM == 10000.0f || MQ135_R0_OHM == 10000.0f) {
    Serial.println(F("[WARN] MQ3_R0_OHM / MQ135_R0_OHM are still the 10000 placeholder: ppm is NOT "
                     "calibrated. Run CALIBRATE_MODE (see README)."));
  }
  Serial.println(F("[CHECK] MQ-3 and MQ-135 VCC must be on the 5V/VIN pin, NOT 3.3 V."));
  Serial.printf("[HW] MQ-3 GPIO%d, MQ-135 GPIO%d, DHT22 GPIO%d, LED GPIO%d | publish every %d s "
                "after a %d s warm-up | WiFi '%s' -> MQTT %s:%d\n",
                PIN_MQ3_AO, PIN_MQ135_AO, PIN_DHT, PIN_LED, SAMPLE_PERIOD_S, WARMUP_S, WIFI_SSID,
                MQTT_HOST, MQTT_PORT);

  netBegin();  // network runs on its own task; sensing below never waits for it
  nextLiveMs = millis() + 2000;
  nextPublishMs = millis() + (uint32_t)WARMUP_S * 1000UL;
}

void loop() {
  const uint32_t now = millis();

  if ((int32_t)(now - nextPublishMs) >= 0) {
    nextPublishMs += (uint32_t)SAMPLE_PERIOD_S * 1000UL;
    if ((int32_t)(now - nextPublishMs) >= 0) nextPublishMs = now + (uint32_t)SAMPLE_PERIOD_S * 1000UL;
    PantrySample s{};
    if (readAll(s, true)) {
      netEnqueue(s);
      Serial.printf("[%5lus] PUBLISH #%lu  MQ-3 ethanol=%7.2f ppm | MQ-135 ammonia=%7.2f ppm | "
                    "T=%4.1fC RH=%4.1f%% | queued for banana + potato | net=%s\n",
                    (unsigned long)(now / 1000), (unsigned long)cycle, s.mq3Ppm, s.mq135Ppm, s.tempC,
                    s.rhPct, netStage());
      cycle++;
      displayShow(s, netStage(), 0);
    } else {
      displayFault("MQ or DHT22 reading", "unusable (see Serial)", netStage());
    }
  } else if (LIVE_PRINT_S > 0 && (int32_t)(now - nextLiveMs) >= 0) {
    nextLiveMs = now + (uint32_t)LIVE_PRINT_S * 1000UL;
    PantrySample s{};
    if (readAll(s, false)) {
      const bool warm = now < (uint32_t)WARMUP_S * 1000UL;
      Serial.printf("[%5lus] live  MQ-3=%7.2f ppm  MQ-135=%7.2f ppm  T=%4.1fC RH=%4.1f%%  net=%s%s\n",
                    (unsigned long)(now / 1000), s.mq3Ppm, s.mq135Ppm, s.tempC, s.rhPct, netStage(),
                    warm ? "  (WARM-UP: not published yet)" : "");
      displayShow(s, netStage(), warm ? (uint32_t)WARMUP_S - now / 1000 : 0);
    } else {
      displayFault("MQ or DHT22 reading", "unusable (see Serial)", netStage());
    }
  }
  delay(50);
}

#endif
