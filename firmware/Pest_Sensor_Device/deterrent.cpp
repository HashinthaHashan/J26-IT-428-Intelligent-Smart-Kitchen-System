#include "deterrent.h"

#include <Arduino.h>
#include <esp_system.h>

// Survives soft/brownout/watchdog resets (not a full power cycle).
RTC_DATA_ATTR static uint8_t rtcMotorWasOn = 0;
RTC_DATA_ATTR static uint8_t rtcCycleIndex = 0;

static DeterrentState state = DS_IDLE;
static bool motorOn = false;
static uint32_t motorOnSince = 0;
static bool ledOn = false;
static bool buzzerOn = false;
static uint32_t buzzerOnSince = 0;

// Running trial
static Condition runCondition = COND_CONTROL;
static TrialRecord running = {};
static uint32_t phaseStart = 0;

static TrialRecord finished = {};
static bool haveFinished = false;
static uint32_t trialCounter = 0;
static uint16_t bootTag = 0;

// ---- low-level outputs ------------------------------------------------------

static void writeMotor(bool on) {
  digitalWrite(PIN_MOTOR, (MOTOR_ACTIVE_HIGH ? on : !on) ? HIGH : LOW);
}

static void setMotor(bool on, uint32_t nowMs) {
  if (on == motorOn) return;
  motorOn = on;
  motorOnSince = nowMs;
  rtcMotorWasOn = on ? 1 : 0;
  writeMotor(on);
}

static void setLed(bool on) {
  ledOn = on;
  digitalWrite(PIN_LED, on ? HIGH : LOW);
}

// PASSIVE buzzer: it needs an oscillating signal, so it is driven with tone()/noTone()
// (hardware PWM on the pin), never with digitalWrite. noTone() only does something while
// a tone is running, so it is called only after tone() (tracked by buzzerOn). After
// noTone() the pin is released at LOW, the right idle level (a constant HIGH would push
// steady current through the coil for no sound).
static void setBuzzer(bool on, uint32_t nowMs) {
  if (on == buzzerOn) return;
  buzzerOn = on;
  if (on) {
    buzzerOnSince = nowMs;
    tone(PIN_BUZZER, BUZZER_TONE_HZ);
  } else {
    noTone(PIN_BUZZER);
  }
}

// ---- state machine ----------------------------------------------------------

static void startTrial(uint32_t nowMs, Condition c, const char *requestId, const char *zone, uint32_t epoch) {
  runCondition = c;
  memset(&running, 0, sizeof running);
  snprintf(running.trialId, sizeof running.trialId, "%s-%04X-%lu", DEVICE_ID, (unsigned)bootTag,
           (unsigned long)trialCounter++);
  strlcpy(running.requestId, requestId ? requestId : "", sizeof running.requestId);
  strlcpy(running.condition, conditionName(c), sizeof running.condition);
  strlcpy(running.zone, zone ? zone : PEST_ZONE, sizeof running.zone);
  running.activationS = ACTIVATION_S;
  running.observationS = OBSERVATION_S;
  running.startEpoch = epoch;
  running.startMs = nowMs;
  state = DS_ACTIVATION;
  phaseStart = nowMs;
  setLed(false);  // the trial owns the LED now (dark unless the condition flashes it)
  // Outputs first: nothing below may delay the physical response.
  if (conditionUsesMotor(c)) setMotor(true, nowMs);
  if (conditionUsesBuzzer(c)) setBuzzer(true, nowMs);  // same activation window as motor/LED
  Serial.printf("[DETERRENT] trial %s START NOW  condition=%s  zone=%s  outputs=[%s%s%s]  camera=%s\n",
                running.trialId, running.condition, running.zone, conditionUsesMotor(c) ? "motor " : "",
                conditionUsesLed(c) ? "led " : "", conditionUsesBuzzer(c) ? "buzzer" : "",
                running.requestId[0] ? running.requestId : "none (offline or rate-limited)");
}

bool deterrentStart(uint32_t nowMs, const char *zone, const char *requestId, uint32_t epoch) {
  if (state != DS_IDLE) return false;
  const Condition c = nextDefaultCondition(rtcCycleIndex);
  startTrial(nowMs, c, requestId, zone, epoch);
  return true;
}

bool deterrentAttachSpecies(const char *requestId, const char *species) {
  if (state == DS_IDLE || !requestId || !requestId[0] || strcmp(requestId, running.requestId) != 0) {
    return false;  // that trial was already published (or never existed)
  }
  // The trial schema only knows rat and cockroach; a non-pest answer stays on the event.
  if (strcmp(species, "rat") != 0 && strcmp(species, "cockroach") != 0) return false;
  strlcpy(running.species, species, sizeof running.species);
  return true;
}

bool deterrentManual(uint32_t nowMs, Condition c, const char *zone, uint32_t epoch) {
  if (state != DS_IDLE) {
    Serial.println(F("[DETERRENT] manual trial IGNORED: a trial is already running"));
    return false;
  }
  startTrial(nowMs, c, "", zone, epoch);
  return true;
}

void deterrentUpdate(uint32_t nowMs, bool online) {
  // Fail-safe: the motor is never on longer than MOTOR_MAX_ON_MS, whatever the state.
  if (motorOn && nowMs - motorOnSince > MOTOR_MAX_ON_MS) {
    Serial.println(F("[DETERRENT] motor ON too long: forced OFF (fail-safe)"));
    setMotor(false, nowMs);
  }
  // Same fail-safe for the buzzer: never sounding longer than BUZZER_MAX_ON_MS.
  if (buzzerOn && nowMs - buzzerOnSince > BUZZER_MAX_ON_MS) {
    Serial.println(F("[DETERRENT] buzzer ON too long: forced OFF (fail-safe)"));
    setBuzzer(false, nowMs);
  }

  switch (state) {
    case DS_ACTIVATION:
      if (conditionUsesLed(runCondition)) setLed(((nowMs - phaseStart) / LED_FLASH_MS) % 2 == 0);
      if (BUZZER_PULSE_MS > 0 && conditionUsesBuzzer(runCondition)) {
        setBuzzer(((nowMs - phaseStart) / BUZZER_PULSE_MS) % 2 == 0, nowMs);
      }
      if (nowMs - phaseStart >= (uint32_t)ACTIVATION_S * 1000UL) {
        setMotor(false, nowMs);
        setBuzzer(false, nowMs);  // sounded for exactly the activation window
        setLed(false);
        state = DS_OBSERVATION;
        phaseStart = nowMs;
        Serial.printf("[DETERRENT] trial %s: activation done, observing for %d s\n", running.trialId,
                      OBSERVATION_S);
      }
      break;
    case DS_OBSERVATION:
      if (nowMs - phaseStart >= (uint32_t)OBSERVATION_S * 1000UL) {
        finished = running;
        haveFinished = true;
        state = DS_IDLE;
        Serial.printf("[DETERRENT] trial %s DONE  species=%s  (verdict: uncertain, needs review in the app)\n",
                      running.trialId, running.species[0] ? running.species : "unknown");
      }
      break;
    default:
      break;
  }

  // Status LED: only when no trial owns it.
  if (state == DS_IDLE) {
    const uint32_t t = nowMs % 3000;
    bool on = false;
    if (online) {
      on = t < 80;                                   // one short blink
    } else {
      on = (t < 80) || (t >= 250 && t < 330);        // two quick blinks
    }
    setLed(on);
  } else if (state == DS_OBSERVATION) {
    setLed(false);
  }
}

bool deterrentTakeFinished(TrialRecord &out) {
  if (!haveFinished) return false;
  out = finished;
  haveFinished = false;
  return true;
}

DeterrentState deterrentState() { return state; }

const char *deterrentStateName() {
  switch (state) {
    case DS_ACTIVATION: return "ACTIVATION";
    case DS_OBSERVATION: return "observation";
    default: return "idle";
  }
}

bool deterrentMotorOn() { return motorOn; }
bool deterrentBuzzerOn() { return buzzerOn; }
uint32_t deterrentTrialCount() { return trialCounter; }

bool deterrentMotorWasOnAtReset() {
  const bool was = rtcMotorWasOn != 0;
  rtcMotorWasOn = 0;
  return was;
}

void deterrentBegin() {
  // Latch the OFF level first, then make the pin an output, so the motor is
  // never pulsed on by the default output latch.
  writeMotor(false);
  pinMode(PIN_MOTOR, OUTPUT);
  writeMotor(false);
  motorOn = false;
  // The buzzer: the pin starts as a plain output at its reset level (LOW) and no tone is
  // running. Nothing ever drives it with digitalWrite; a reset also stops any tone.
  pinMode(PIN_BUZZER, OUTPUT);
  buzzerOn = false;
  digitalWrite(PIN_LED, LOW);
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, LOW);
  bootTag = (uint16_t)(esp_random() & 0xFFFF);
}

void deterrentHardwareTestStep() {
  static uint8_t step = 0;
  switch (step++ % 8) {
    case 0:
      Serial.printf("[TEST] MOTOR ON (GPIO%d driven %s). The motor should vibrate now.\n", PIN_MOTOR,
                    MOTOR_ACTIVE_HIGH ? "HIGH" : "LOW");
      setMotor(true, millis());
      break;
    case 1:
      Serial.printf("[TEST] MOTOR OFF (GPIO%d driven %s). It should stop. If it ran during the OFF step "
                    "instead, flip MOTOR_ACTIVE_HIGH in config.h.\n",
                    PIN_MOTOR, MOTOR_ACTIVE_HIGH ? "LOW" : "HIGH");
      setMotor(false, millis());
      break;
    case 2:
      Serial.printf("[TEST] LED ON (GPIO%d HIGH). The LED should light.\n", PIN_LED);
      setLed(true);
      break;
    case 3:
      Serial.println(F("[TEST] LED OFF."));
      setLed(false);
      break;
    case 4:
      Serial.printf("[TEST] BUZZER: on, tone(GPIO%d, %dHz). LISTEN: a steady tone. Volume is FAINT on direct GPIO "
                    "drive: this is expected until a transistor switch is added (see README).\n",
                    PIN_BUZZER, BUZZER_TONE_HZ);
      setBuzzer(true, millis());
      break;
    case 5:
      Serial.printf("[TEST] BUZZER: off, noTone(GPIO%d). It should go silent. If the ON step gave only a single "
                    "faint 'tik' that is a constant level, not a tone. If it was silent, check the wiring: the longer "
                    "(+) leg to GPIO%d, the shorter (-) leg to GND.\n",
                    PIN_BUZZER, PIN_BUZZER);
      setBuzzer(false, millis());
      break;
    case 6:
      Serial.println(F("[TEST] MOTOR + LED + BUZZER together for 3 s. WATCH for a reset or 'BROWNOUT' on Serial:"));
      Serial.println(F("[TEST]   a reboot here means the motor/buzzer load is dragging the 3.3 V/5 V rail down."));
      Serial.println(F("[TEST]   Fix: power the motor driver from its own 5 V supply, GND shared with the ESP32."));
      setMotor(true, millis());
      setLed(true);
      setBuzzer(true, millis());
      break;
    default:
      Serial.println(F("[TEST] all OFF. Cycle repeats; live sensor levels are printed between steps."));
      setMotor(false, millis());
      setLed(false);
      setBuzzer(false, millis());
      break;
  }
}

int deterrentSelfTest() {
  int fails = 0;
  Condition c;
  fails += !conditionFromName("vibration_led", c) || c != COND_VIBRATION_LED;
  fails += !conditionFromName("control", c) || c != COND_CONTROL;
  fails += conditionFromName("ultrasonic", c);  // no ultrasonic hardware exists
  fails += conditionUsesMotor(COND_LED_ONLY) || !conditionUsesMotor(COND_VIBRATION_ONLY);
  fails += conditionUsesLed(COND_VIBRATION_ONLY) || !conditionUsesLed(COND_VIBRATION_LED);
  // Buzzer mapping follows BUZZER_ON_CONDITIONS and never changes the condition names.
  for (int i = 0; i < COND_COUNT; i++) {
    const bool expected = BUZZER_ENABLED && (((BUZZER_ON_CONDITIONS) >> i) & 1);
    fails += conditionUsesBuzzer((Condition)i) != expected;
  }
  uint8_t idx = 0;
  Condition seq[5];
  for (int i = 0; i < 5; i++) seq[i] = nextDefaultCondition(idx);
  if (EXPERIMENT_MODE) {
    fails += seq[0] != COND_CONTROL || seq[1] != COND_VIBRATION_ONLY || seq[2] != COND_LED_ONLY ||
             seq[3] != COND_VIBRATION_LED || seq[4] != COND_CONTROL;  // wraps around
  }
  return fails;
}
