// =============================================================================
// KitchenGuard - Component 03: Pest detection, BOARD 1 (sensors + deterrent)
//
//   PIR / IR / vibration (debounced) -> PestEvent over MQTT
//   ANY of them        -> a deterrent trial starts IMMEDIATELY (no waiting on anything)
//                      -> and, in parallel, a camera photo is requested (capture_request)
//
// Board 1 never talks to the camera board directly: the backend relays the request,
// classifies the photo with YOLO, and sends the species back as a "classification"
// command, which is only ATTACHED to the trial that is already running.
//
//   sensors.*      debounced PIR / IR / vibration
//   deterrent.*    trial state machine, vibration motor + LED, fail-safes
//   mqtt_client.*  WiFi + MQTT task, offline queue, diagnostics
//
// Edge failsafe: sensing, debouncing and the deterrent run in loop() (core 1) with no
// network at all. The network task (core 0) only moves data.
// =============================================================================

#include <Arduino.h>
#include <esp_system.h>
#include <esp_task_wdt.h>

#include "config.h"
#include "deterrent.h"
#include "mqtt_client.h"
#include "sensors.h"

static void logResetReason() {
  const esp_reset_reason_t r = esp_reset_reason();
  const char *name = "UNKNOWN";
  switch (r) {
    case ESP_RST_POWERON: name = "POWER-ON (normal cold start)"; break;
    case ESP_RST_SW: name = "software restart"; break;
    case ESP_RST_PANIC: name = "PANIC (crash)"; break;
    case ESP_RST_INT_WDT:
    case ESP_RST_TASK_WDT:
    case ESP_RST_WDT: name = "WATCHDOG (loop() hung, the safety watchdog reset the chip)"; break;
    case ESP_RST_BROWNOUT: name = "BROWNOUT (power rail dropped!)"; break;
    default: break;
  }
  Serial.printf("[BOOT] reset reason: %s\n", name);
  // The RTC flag survives the reset: was the motor running when the chip went down?
  const bool motorWasOn = deterrentMotorWasOnAtReset();
  if (motorWasOn && r != ESP_RST_POWERON) {
    Serial.println(F("[BOOT] !! The chip reset WHILE THE VIBRATION MOTOR WAS RUNNING."));
    Serial.println(F("[BOOT] !! The motor driver is pulling the supply down. Power the motor driver from its"));
    Serial.println(F("[BOOT] !! OWN 5 V supply and share GND with the ESP32 (do not feed it from the ESP32 pin)."));
    Serial.println(F("[BOOT] !! Also add 10 k from the driver IN to GND and a 470 uF capacitor across the motor supply."));
  } else if (r == ESP_RST_BROWNOUT) {
    Serial.println(F("[BOOT] Brownout without the motor running: check the USB cable/port and the 5 V supply."));
  }
}

static void startWatchdog() {
  esp_task_wdt_config_t cfg = {};
  cfg.timeout_ms = (uint32_t)WATCHDOG_S * 1000UL;
  cfg.idle_core_mask = 0;  // only watch loop(), not the idle tasks
  cfg.trigger_panic = true;
  if (esp_task_wdt_init(&cfg) == ESP_ERR_INVALID_STATE) esp_task_wdt_reconfigure(&cfg);
  esp_task_wdt_add(nullptr);  // the Arduino loop task
}

// ---------------------------------------------------------------------------
// Bench test
// ---------------------------------------------------------------------------
#if HARDWARE_TEST_MODE

void setup() {
  Serial.begin(115200);
  delay(300);
  deterrentBegin();
  sensorsBegin();
  Serial.println();
  Serial.println(F("=== KitchenGuard PEST board: HARDWARE TEST MODE ==="));
  logResetReason();
  Serial.println(F("Watch and listen: follow the [TEST] prompts. Between steps the RAW pin levels"));
  Serial.println(F("are printed: wave a hand at the PIR, tap the vibration sensor, hold something near the IR."));
  Serial.println(F("A level that changes tells you its polarity; set PIR/VIB/IR_ACTIVE_HIGH to match."));
}

void loop() {
  static uint32_t nextStep = 0, nextLevels = 0;
  const uint32_t now = millis();
  if ((int32_t)(now - nextStep) >= 0) {
    nextStep = now + 3000;
    deterrentHardwareTestStep();
  }
  if ((int32_t)(now - nextLevels) >= 0) {
    nextLevels = now + 500;
    int pir, ir, vib;
    sensorsRawLevels(pir, ir, vib);
    Serial.printf("   raw levels: PIR(GPIO%d)=%d  IR(GPIO%d)=%d  VIB(GPIO%d)=%d   (PIR needs %ds warm-up)\n",
                  PIN_PIR, pir, PIN_IR, ir, PIN_VIB, vib, PIR_WARMUP_S);
  }
  delay(20);
}

// ---------------------------------------------------------------------------
// Normal operation
// ---------------------------------------------------------------------------
#else

static uint32_t captureSeq = 0;
static uint32_t lastCaptureAskMs = 0;
static bool everAsked = false;
static uint32_t nextHeartbeatMs = 0;

static void handleTrigger(TriggerSource src, uint32_t now) {
  // DECISION (deliberate): PIR, IR and vibration may ALL start a deterrent trial.
  // Earlier, IR alone was treated as weak evidence (presence only) and only logged. That
  // is overridden: missing a real pest matters more right now than the occasional wasted
  // activation from an IR false positive. Which OUTPUT a trial uses (including none, for
  // the "control" condition) is a separate decision made by the experiment cycle.
  const uint32_t epoch = netEpochNow();

  // A capture id for the photo requested alongside the trial (rate limited so a burst of
  // triggers cannot flood the camera). Preparing it costs microseconds.
  char requestId[24] = "";
  const bool rateOk = !everAsked || now - lastCaptureAskMs >= CAPTURE_MIN_INTERVAL_MS;
  if (rateOk) {
    snprintf(requestId, sizeof requestId, "pk-%lu-%lu", (unsigned long)captureSeq++, (unsigned long)(now % 100000));
  }

  // 1) THE DETERRENT FIRST: outputs switch on now, before any network or logging work.
  const bool started = deterrentStart(now, PEST_ZONE, requestId, epoch);

  // 2) Then, fire-and-forget: the photo request and the event record.
  const SensorLevels levels = sensorsRead();
  const bool asked = rateOk && netSendCaptureRequest(requestId, triggerName(src), PEST_ZONE, epoch);
  if (asked) {
    everAsked = true;
    lastCaptureAskMs = now;
  }

  OutRec ev{};
  ev.kind = OUT_EVENT;
  ev.epoch = epoch;
  ev.ms = now;
  strlcpy(ev.trigger, triggerName(src), sizeof ev.trigger);
  strlcpy(ev.zone, PEST_ZONE, sizeof ev.zone);
  ev.pir = levels.pir;
  ev.vibTrigger = src == SRC_VIB;
  ev.vibRmsG = levels.vib ? 1.0f : 0.0f;  // PLACEHOLDER: digital sensor, no real RMS
  ev.cameraAsked = asked;
  netEnqueue(ev);

  Serial.printf("[%5lus] TRIGGER %s  zone=%s  trial=%s  camera=%s  net=%s\n", (unsigned long)(now / 1000), ev.trigger,
                PEST_ZONE, started ? "STARTED" : "not started (one is already running)",
                asked ? requestId : (rateOk ? "not possible (offline/clock)" : "skipped (asked <5 s ago)"),
                netStage());
}

static void handleCommands(uint32_t now) {
  DeviceCommand c;
  while (netPollCommand(c)) {
    if (strcmp(c.action, "classification") == 0) {
      // The camera's species answer. It never starts or stops anything: it is attached to
      // the trial that this photo was requested for, if that trial is still running.
      const bool attached = deterrentAttachSpecies(c.requestId, c.species);
      Serial.printf("[CMD] camera says %s (%.2f) for request %s -> %s\n", c.species[0] ? c.species : "?",
                    c.confidence, c.requestId,
                    attached ? "ATTACHED to the running trial"
                             : "not attached (that trial already finished, or the answer is not rat/cockroach); "
                               "it stays on the event only");
    } else if (strcmp(c.source, "manual") == 0) {
      // Manual test: runs the named condition right now.
      Condition cond;
      if (!conditionFromName(c.condition, cond)) {
        Serial.printf("[CMD] manual deterrent IGNORED: unknown condition '%s'\n", c.condition);
        continue;
      }
      const bool ok = deterrentManual(now, cond, PEST_ZONE, netEpochNow());
      Serial.printf("[CMD] manual deterrent '%s' -> %s\n", c.condition, ok ? "STARTED" : "IGNORED (busy)");
    } else {
      Serial.printf("[CMD] deterrent command from source '%s' IGNORED: only manual tests start a trial this way\n",
                    c.source);
    }
  }
}

static void publishFinishedTrial() {
  TrialRecord t;
  while (deterrentTakeFinished(t)) {
    OutRec rec{};
    rec.kind = OUT_TRIAL;
    rec.epoch = t.startEpoch;
    rec.ms = t.startMs;
    strlcpy(rec.trialId, t.trialId, sizeof rec.trialId);
    strlcpy(rec.species, t.species, sizeof rec.species);
    strlcpy(rec.condition, t.condition, sizeof rec.condition);
    strlcpy(rec.zone, t.zone, sizeof rec.zone);
    rec.activationS = t.activationS;
    rec.observationS = t.observationS;
    netEnqueue(rec);
  }
}

void setup() {
  // The very first thing: motor OFF, LED off.
  deterrentBegin();
  Serial.begin(115200);
  delay(300);
  Serial.println();
  Serial.println(F("=== KitchenGuard pest SENSOR board, device " DEVICE_ID " ==="));
  logResetReason();
  sensorsBegin();

#if RUN_SELFTEST
  Serial.printf("[SELFTEST] debounce=%s deterrent-logic=%s\n", sensorsSelfTest() ? "FAIL" : "ok",
                deterrentSelfTest() ? "FAIL" : "ok");
#endif

  Serial.printf("[HW] PIR GPIO%d  IR GPIO%d  VIB GPIO%d | motor GPIO%d  LED GPIO%d  buzzer GPIO%d | zone '%s' | "
                "WiFi '%s' -> MQTT %s:%d\n",
                PIN_PIR, PIN_IR, PIN_VIB, PIN_MOTOR, PIN_LED, PIN_BUZZER, PEST_ZONE, WIFI_SSID, MQTT_HOST, MQTT_PORT);
  Serial.printf("[HW] PIR ignored for the first %d s (warm-up). Deterrent: vibration + LED + buzzer "
                "(no ultrasonic hardware, no speaker). Experiment cycle %s.\n",
                PIR_WARMUP_S, EXPERIMENT_MODE ? "ON" : "OFF (always " DEFAULT_CONDITION ")");

  startWatchdog();
  netBegin();  // network runs on its own task; nothing below ever waits for it
  nextHeartbeatMs = millis() + 10000;
}

void loop() {
  esp_task_wdt_reset();
  const uint32_t now = millis();

  const uint8_t fired = sensorsPoll(now);
  for (int s = 0; s < SRC_COUNT; s++) {
    if (fired & (1 << s)) handleTrigger((TriggerSource)s, now);
  }
  handleCommands(now);
  deterrentUpdate(now, netIsOnline());
  publishFinishedTrial();

  if ((int32_t)(now - nextHeartbeatMs) >= 0) {
    nextHeartbeatMs = now + 10000;
    const SensorLevels l = sensorsRead();
    Serial.printf("[%5lus] state=%s  PIR=%d IR=%d VIB=%d  motor=%s  buzzer=%s  trials=%lu  queued=%lu  net=%s%s\n",
                  (unsigned long)(now / 1000), deterrentStateName(), l.pir, l.ir, l.vib,
                  deterrentMotorOn() ? "ON" : "off", deterrentBuzzerOn() ? "ON" : "off",
                  (unsigned long)deterrentTrialCount(),
                  (unsigned long)netQueued(), netStage(),
                  now < (uint32_t)PIR_WARMUP_S * 1000UL ? "  (PIR WARM-UP)" : "");
  }
  delay(5);
}

#endif
