#include "actuators.h"

#include <Arduino.h>
#include <ESP32Servo.h>

#include "config.h"

static Servo windowServo;

// Applied (effective) state
static bool fanOn = false;
static float windowFrac = 0.0f;       // commanded 0..1
static float servoAngle = SERVO_CLOSED_DEG;  // actual, slewed toward the command
static bool buzzerOn = false;

// Automatic targets from the tier
static Tier activeTier = TIER_SAFE;
static bool autoFan = false;
static float autoWindow = 0.0f;

// Manual holds: -1 = none
static int8_t manualFan = -1;
static float manualWindow = -1.0f;
static uint32_t manualFanAt = 0;
static uint32_t manualWindowAt = 0;

static uint32_t lastUpdateMs = 0;

// ---- low-level outputs ------------------------------------------------------

static void writeRelay(bool on) {
  const bool level = RELAY_ACTIVE_LOW ? !on : on;
  digitalWrite(PIN_RELAY, level ? HIGH : LOW);
}

static void writeBuzzer(bool on) {
  digitalWrite(PIN_BUZZER, (BUZZER_ACTIVE_HIGH ? on : !on) ? HIGH : LOW);
}

static float fracToAngle(float frac) {
  if (frac < 0) frac = 0;
  if (frac > 1) frac = 1;
  return SERVO_CLOSED_DEG + frac * (SERVO_OPEN_DEG - SERVO_CLOSED_DEG);
}

// ---- resolve auto/manual ----------------------------------------------------

// The fan and the window are resolved INDEPENDENTLY: each one reads only its own
// manual hold and its own auto target. (Critical is the one deliberate exception:
// it forces both on for safety.) Every change is logged with its cause so a
// surprising state change can be traced from Serial alone.
static void resolve() {
  bool wantFan = manualFan >= 0 ? (manualFan == 1) : autoFan;
  float wantWindow = manualWindow >= 0 ? manualWindow : autoWindow;
  const char *fanWhy = manualFan >= 0 ? "manual hold" : "auto from tier";
  const char *windowWhy = manualWindow >= 0 ? "manual hold" : "auto from tier";
  if (activeTier == TIER_CRITICAL) {
    // Safety wins: the fan is on and the window at least at the Critical level.
    if (!wantFan) fanWhy = "CRITICAL override";
    wantFan = true;
    if (wantWindow < WINDOW_FRAC_CRITICAL) {
      wantWindow = WINDOW_FRAC_CRITICAL;
      windowWhy = "CRITICAL override";
    }
  }
  if (wantFan != fanOn) {
    Serial.printf("[ACT] fan %s -> %s (%s, active tier %s)\n", fanOn ? "ON" : "OFF",
                  wantFan ? "ON" : "OFF", fanWhy, tierName(activeTier));
    fanOn = wantFan;
    writeRelay(fanOn);
  }
  if (fabsf(wantWindow - windowFrac) > 0.001f) {
    Serial.printf("[ACT] window %d%% -> %d%% (%s, active tier %s)\n",
                  (int)(windowFrac * 100.0f + 0.5f), (int)(wantWindow * 100.0f + 0.5f),
                  windowWhy, tierName(activeTier));
  }
  windowFrac = wantWindow;
}

const char *actuatorsHolds() {
  static char buf[16];
  snprintf(buf, sizeof buf, "%s%s", manualFan >= 0 ? "fan " : "",
           manualWindow >= 0 ? "window" : "");
  return buf;
}

void actuatorsBegin() {
  // Drive every output to its safe/off level before anything else.
  // Latch the OFF level first, then switch the pin to OUTPUT, so an active-LOW
  // relay is never pulsed on by the default LOW output latch.
  writeRelay(false);
  pinMode(PIN_RELAY, OUTPUT);
  writeRelay(false);
  writeBuzzer(false);
  pinMode(PIN_BUZZER, OUTPUT);
  writeBuzzer(false);

  windowServo.setPeriodHertz(50);
  windowServo.attach(PIN_SERVO, SERVO_MIN_US, SERVO_MAX_US);
  windowServo.write((int)SERVO_CLOSED_DEG);  // parks CLOSED (old sketch parked open)
  servoAngle = SERVO_CLOSED_DEG;
  lastUpdateMs = millis();
}

void actuatorsApplyTier(Tier tier, bool tierChanged, uint32_t nowMs) {
  (void)nowMs;
  activeTier = tier;
  if (tierChanged) {  // new situation: drop any manual override
    manualFan = -1;
    manualWindow = -1.0f;
  }
  switch (tier) {
    case TIER_DANGEROUS:
      autoFan = true;
      autoWindow = WINDOW_FRAC_DANGEROUS;
      break;
    case TIER_CRITICAL:
      autoFan = true;
      autoWindow = WINDOW_FRAC_CRITICAL;
      break;
    default:  // Safe, Warning
      autoFan = false;
      autoWindow = 0.0f;
      break;
  }
  resolve();
}

void actuatorsUpdate(uint32_t nowMs) {
  // Manual hold expiry
  if (manualFan >= 0 && nowMs - manualFanAt > (uint32_t)MANUAL_HOLD_S * 1000UL) {
    manualFan = -1;
  }
  if (manualWindow >= 0 && nowMs - manualWindowAt > (uint32_t)MANUAL_HOLD_S * 1000UL) {
    manualWindow = -1.0f;
  }
  resolve();

  // Buzzer pattern follows the active tier
  bool wantBuzzer = false;
  if (activeTier == TIER_CRITICAL) {
    wantBuzzer = true;
  } else if (activeTier == TIER_DANGEROUS) {
    wantBuzzer = ((nowMs / BUZZER_PULSE_MS) % 2) == 0;
  }
  if (wantBuzzer != buzzerOn) {
    buzzerOn = wantBuzzer;
    writeBuzzer(buzzerOn);
  }
  // Log the buzzer MODE (not every pulse). The buzzer is automatic-only.
  static int8_t lastMode = -1;
  const int8_t mode = activeTier == TIER_CRITICAL ? 2 : (activeTier == TIER_DANGEROUS ? 1 : 0);
  if (mode != lastMode) {
    lastMode = mode;
    Serial.printf("[ACT] buzzer mode: %s (active tier %s)\n",
                  mode == 2 ? "CONTINUOUS" : (mode == 1 ? "PULSING 500/500 ms" : "off"),
                  tierName(activeTier));
  }

  // Servo slew toward the commanded angle
  const float target = fracToAngle(windowFrac);
  const float dt = (nowMs - lastUpdateMs) / 1000.0f;
  lastUpdateMs = nowMs;
  if (fabsf(target - servoAngle) > 0.25f) {
    const float step = SERVO_SLEW_DEG_PER_S * dt;
    if (fabsf(target - servoAngle) <= step) {
      servoAngle = target;
    } else {
      servoAngle += (target > servoAngle) ? step : -step;
    }
    windowServo.write((int)(servoAngle + 0.5f));
  }
}

bool actuatorsManualFan(bool on, uint32_t nowMs, const char **why) {
  if (activeTier == TIER_CRITICAL && !on) {
    if (why) *why = "refused: tier is Critical (>=700 ppm), fan must stay on";
    return false;
  }
  manualFan = on ? 1 : 0;
  manualFanAt = nowMs;
  resolve();
  return true;
}

bool actuatorsManualWindow(float frac, uint32_t nowMs, const char **why) {
  if (frac < 0) frac = 0;
  if (frac > 1) frac = 1;
  if (activeTier == TIER_CRITICAL && frac < WINDOW_FRAC_CRITICAL) {
    if (why) *why = "refused: tier is Critical (>=700 ppm), window must stay open";
    return false;
  }
  manualWindow = frac;
  manualWindowAt = nowMs;
  resolve();
  return true;
}

bool actuatorsFanOn() { return fanOn; }
float actuatorsWindowFrac() { return windowFrac; }
bool actuatorsBuzzerOn() { return buzzerOn; }

// ---- bench test -------------------------------------------------------------

void actuatorsHardwareTestTick() {
  static uint8_t step = 0;
  Serial.println();
  switch (step++ % 6) {
    case 0:
      Serial.printf("[TEST] RELAY: driving GPIO%d to the 'ON' level (%s). "
                    "Listen for a click and check the fan.\n",
                    PIN_RELAY, RELAY_ACTIVE_LOW ? "LOW" : "HIGH");
      writeRelay(true);
      break;
    case 1:
      Serial.printf("[TEST] RELAY: 'OFF' level (%s). If the fan ran in the "
                    "previous step the polarity setting is CORRECT; if it ran "
                    "now instead, flip RELAY_ACTIVE_LOW in config.h.\n",
                    RELAY_ACTIVE_LOW ? "HIGH" : "LOW");
      writeRelay(false);
      break;
    case 2:
      Serial.println("[TEST] SERVO: moving to CLOSED angle. The flap should be shut.");
      windowServo.write((int)SERVO_CLOSED_DEG);
      break;
    case 3:
      Serial.println("[TEST] SERVO: moving to OPEN angle. The flap should be open. "
                     "If it is reversed, swap SERVO_CLOSED_DEG / SERVO_OPEN_DEG.");
      windowServo.write((int)SERVO_OPEN_DEG);
      break;
    case 4:
      Serial.println("[TEST] BUZZER: on.");
      writeBuzzer(true);
      break;
    default:
      Serial.println("[TEST] BUZZER: off. Back to the start...");
      writeBuzzer(false);
      windowServo.write((int)SERVO_CLOSED_DEG);
      break;
  }
}
