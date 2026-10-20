// =============================================================================
// KitchenGuard - Component 01: LPG leak detection (ESP32 Dev Kit)
//
//   sensors.*      MQ-2 analog + DHT22, ADC -> Rs -> ppm
//   features.*     the 9 engineered features (mirrors the backend)
//   tier_logic.h   rules, 700 ppm hard override, debouncer
//   model.h        trained Random Forest if lpg_rf_esp32.h exists, else rules
//   actuators.*    relay (fan), servo (window), buzzer
//   mqtt_client.*  WiFi + MQTT on its own task, never blocks sensing
//
// Edge failsafe: setup()/loop() below (core 1) sense, classify, apply the safety
// override and actuate WITHOUT any network. The network task only moves data.
// See README.md for wiring checks, calibration and flashing.
// =============================================================================

#include <Arduino.h>
#include <esp_system.h>

#include "actuators.h"
#include "config.h"
#include "features.h"
#include "model.h"
#include "mqtt_client.h"
#include "sensors.h"
#include "tier_logic.h"

#if CALIBRATE_MODE && HARDWARE_TEST_MODE
#error "Enable only one of CALIBRATE_MODE and HARDWARE_TEST_MODE"
#endif

// ---------------------------------------------------------------------------
// Calibration mode
// ---------------------------------------------------------------------------
#if CALIBRATE_MODE

static const int CAL_WINDOW = 60;  // readings used for the stability verdict
static float calRs[CAL_WINDOW];
static int calCount = 0;
static int calHead = 0;

void setup() {
  Serial.begin(115200);
  delay(300);
  sensorsBegin();
  Serial.println();
  Serial.println(F("=== KitchenGuard MQ-2 CALIBRATION MODE ==="));
  Serial.println(F("Run in CLEAN AIR after the 48 h burn-in, sensor warm for >= 10 min."));
  Serial.println(F("When stab(60s) stays under ~2% for a few minutes, copy the last"));
  Serial.println(F("'Suggested MQ2_R0_OHM' value into config.h, then set CALIBRATE_MODE false."));
  Serial.println(F("Columns: adc=raw 0-4095 count | pin=mV at GPIO34 | AO=mV at sensor | "
                   "Rs=ohm | Rs/RL | stab=std-dev % of Rs over last 60 s"));
}

void loop() {
  static uint32_t next = 0;
  const uint32_t now = millis();
  if ((int32_t)(now - next) < 0) return;
  next = now + 1000;

  const int rawAdc = analogRead(PIN_MQ2_AO);
  const Mq2Reading r = sensorsReadMq2();
  if (!r.valid) {
    Serial.printf("adc=%4d pin=%5.0fmV  SENSOR FAULT: AO ~0 V (unpowered or wire off?)\n",
                  rawAdc, r.pinMv);
    return;
  }

  calRs[calHead] = r.rsOhm;
  calHead = (calHead + 1) % CAL_WINDOW;
  if (calCount < CAL_WINDOW) calCount++;
  float mean = 0;
  for (int i = 0; i < calCount; i++) mean += calRs[i];
  mean /= calCount;
  float var = 0;
  for (int i = 0; i < calCount; i++) var += (calRs[i] - mean) * (calRs[i] - mean);
  const float stabPct = calCount > 1 ? 100.0f * sqrtf(var / calCount) / mean : 100.0f;

  Serial.printf("adc=%4d pin=%5.0fmV AO=%5.0fmV Rs=%8.0f ohm Rs/RL=%6.3f stab(%2ds)=%5.2f%% "
                "%s | Suggested MQ2_R0_OHM = %.0f\n",
                rawAdc, r.pinMv, r.aoMv, r.rsOhm, r.rsOhm / MQ2_RL_OHM, calCount, stabPct,
                (calCount >= CAL_WINDOW && stabPct < 2.0f) ? "STABLE" : "settling",
                mean / MQ2_CLEAN_AIR_RATIO);
}

// ---------------------------------------------------------------------------
// Hardware bench test mode
// ---------------------------------------------------------------------------
#elif HARDWARE_TEST_MODE

void setup() {
  Serial.begin(115200);
  delay(300);
  actuatorsBegin();
  Serial.println();
  Serial.println(F("=== KitchenGuard HARDWARE TEST MODE ==="));
  Serial.println(F("Watch/listen to the relay, flap and buzzer and follow the prompts."));
}

void loop() {
  static uint32_t next = 0;
  const uint32_t now = millis();
  if ((int32_t)(now - next) < 0) return;
  next = now + 4000;
  actuatorsHardwareTestTick();
}

// ---------------------------------------------------------------------------
// Normal operation
// ---------------------------------------------------------------------------
#else

static FeatureWindow window;
static TierDebouncer debouncer;
static uint32_t seq = 0;
static uint32_t nextSampleMs = 0;

// Why did the chip (re)start? A BROWNOUT here means the power rail sagged, which
// is the classic symptom of a servo/relay sharing a weak supply.
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
    case ESP_RST_DEEPSLEEP: name = "deep sleep wake"; break;
    default: break;
  }
  Serial.printf("[BOOT] reset reason: %s\n", name);
  if (r == ESP_RST_BROWNOUT) {
    Serial.println(F("[BOOT] The ESP32 lost power briefly. If this appears when the window moves or the "
                     "relay switches, the supply/grounding is the problem, not the software."));
  }
}

static void handleManualCommands(uint32_t now) {
  ManualCommand c;
  while (netPollCommand(c)) {
    const char *why = nullptr;
    bool ok;
    const bool fanBefore = actuatorsFanOn();
    const int windowBefore = (int)(actuatorsWindowFrac() * 100.0f + 0.5f);
    if (strcmp(c.action, "fan") == 0) {
      ok = actuatorsManualFan(c.value >= 0.5f, now, &why);
    } else {
      ok = actuatorsManualWindow(c.value, now, &why);
    }
    // Shows the active tier and fan/window BEFORE and AFTER, so it is obvious
    // whether a command touched only the actuator it targeted.
    Serial.printf("[CMD] %s=%.2f (source=%s) active tier=%s | fan %s->%s  window %d%%->%d%% | %s%s%s\n",
                  c.action, c.value, c.source, tierName(debouncer.active()),
                  fanBefore ? "ON" : "OFF", actuatorsFanOn() ? "ON" : "OFF", windowBefore,
                  (int)(actuatorsWindowFrac() * 100.0f + 0.5f), ok ? "APPLIED" : "IGNORED",
                  ok ? "" : " - ", ok ? "" : (why ? why : ""));
  }
}

static void sampleTick(uint32_t now) {
  const Mq2Reading mq = sensorsReadMq2();
  const DhtReading dht = sensorsReadDht();

  if (!mq.valid) {
    // AO ~0 V means no sensor signal, which is NOT the same as clean air.
    // Keep the current actuation and say so loudly; do not publish bogus data.
    Serial.printf("[%5lus] SENSOR FAULT: MQ-2 AO ~0 V (pin=%.0f mV). Holding state.\n",
                  (unsigned long)(now / 1000), mq.pinMv);
    return;
  }

  // DEBUG_FORCE_PPM (config.h) replaces the sensor value to exercise the tiers
  // without gas. -1 = off = real sensor.
  const float ppmNow = DEBUG_FORCE_PPM >= 0 ? (float)DEBUG_FORCE_PPM : mq.ppm;
  window.push(ppmNow, dht.rhPct);
  const FeatureVector f = window.compute(dht.tempC);

  const Tier modelTier = modelPredict(f);
  const Tier rawTier = applySafetyOverride(modelTier, f.ppm_comp);  // life-safety
  const Tier active = debouncer.update(rawTier, f.ppm_comp);
  actuatorsApplyTier(active, debouncer.changed(), now);

  const bool onlineNow = netIsOnline();
  TelemetrySample s{};
  s.seq = seq;
  s.epoch = netEpochNow();
  s.ms = now;
  s.ppm = f.ppm_comp;
  s.tempC = dht.tempC;
  s.rhPct = dht.rhPct;
  s.windowFrac = actuatorsWindowFrac();
  s.tier = (uint8_t)active;
  s.fanOn = actuatorsFanOn();
  s.offline = !onlineNow;
  netEnqueueTelemetry(s);

  Serial.printf("[%5lus] ppm=%7.1f tier=%-9s (raw %-9s%s) fan=%-3s win=%3d%% T=%4.1fC RH=%4.1f%%%s net=%s seq=%lu%s%s%s%s%s\n",
                (unsigned long)(now / 1000), f.ppm_comp, tierName(active), tierName(rawTier),
                f.ppm_comp >= TIER_CRITICAL_PPM ? " OVERRIDE" : "",
                s.fanOn ? "ON" : "OFF", (int)(s.windowFrac * 100.0f + 0.5f), dht.tempC,
                dht.rhPct, dht.fresh ? "" : "(DHT stale)", netStage(),
                (unsigned long)seq, now < (uint32_t)WARMUP_S * 1000UL ? " WARMUP" : "",
                DEBUG_FORCE_PPM >= 0 ? " [DEBUG: PPM FORCED]" : "",
                actuatorsHolds()[0] ? " hold=[" : "", actuatorsHolds(),
                actuatorsHolds()[0] ? "]" : "");
  seq++;
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println(F("=== KitchenGuard LPG device " DEVICE_ID " ==="));
  logResetReason();
  if (DEBUG_FORCE_PPM >= 0) {
    Serial.printf("[WARN] DEBUG_FORCE_PPM = %d: the gas sensor is IGNORED and telemetry carries a "
                  "fake ppm. Set it back to -1 before real use.\n", (int)DEBUG_FORCE_PPM);
  }

  actuatorsBegin();  // outputs to their safe levels first
  sensorsBegin();

#if RUN_SELFTEST
  const int fFeat = featuresSelfTest();
  const int fSens = sensorsSelfTest();
  const int fTier = tierLogicSelfTest();
  Serial.printf("[SELFTEST] features=%s sensors=%s tier-logic=%s\n", fFeat ? "FAIL" : "ok",
                fSens ? "FAIL" : "ok", fTier ? "FAIL" : "ok");
#endif

  Serial.printf("[MODEL] %s\n", modelDescription());
  if (!modelIsTrained()) {
    Serial.println(F("[WARN] Running the RULE FALLBACK (150/300/700 ppm), not the trained model."));
  }
  if (MQ2_R0_OHM == 10000.0f) {
    Serial.println(F("[WARN] MQ2_R0_OHM is still the 10000 placeholder - ppm is NOT calibrated."));
  }
  Serial.printf("[HW] relay active-%s | servo %d..%d deg | WiFi '%s' -> MQTT %s:%d\n",
                RELAY_ACTIVE_LOW ? "LOW" : "HIGH", (int)SERVO_CLOSED_DEG, (int)SERVO_OPEN_DEG,
                WIFI_SSID, MQTT_HOST, MQTT_PORT);

  netBegin();  // network runs on its own task; sensing below never waits for it
  nextSampleMs = millis() + SAMPLE_PERIOD_MS;
}

void loop() {
  const uint32_t now = millis();

  actuatorsUpdate(now);        // buzzer pattern, servo slew, manual-hold expiry
  handleManualCommands(now);

  if ((int32_t)(now - nextSampleMs) >= 0) {
    nextSampleMs += SAMPLE_PERIOD_MS;  // fixed 1 Hz grid, no drift
    if ((int32_t)(now - nextSampleMs) >= 0) nextSampleMs = now + SAMPLE_PERIOD_MS;  // fell behind
    sampleTick(now);
  }
  delay(10);
}

#endif
