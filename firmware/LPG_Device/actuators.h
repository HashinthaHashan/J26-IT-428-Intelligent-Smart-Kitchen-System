// Fan relay, window servo and buzzer.
//
// Automatic behaviour per ACTIVE (debounced, override-applied) tier:
//   Safe       fan OFF, window   0 %, buzzer off
//   Warning    fan OFF, window   0 %, buzzer off   (dashboard alert only)
//   Dangerous  fan ON,  window  45 %, buzzer pulsing 500 ms on / 500 ms off
//   Critical   fan ON,  window  90 %, buzzer continuous
//
// Manual commands (from the app via MQTT) are obeyed, except that at Critical a
// command that would turn the fan off or close the window below the Critical
// level is REFUSED. A manual setting is held until the active tier changes or
// MANUAL_HOLD_S passes; then automatic control resumes.
#pragma once

#include <stdint.h>

#include "tier_logic.h"

void actuatorsBegin();

// Call once per 1 Hz sample with the active tier. `tierChanged` is true only on
// the sample where the debounced tier changed (clears manual holds).
void actuatorsApplyTier(Tier tier, bool tierChanged, uint32_t nowMs);

// Call every loop pass (~100 Hz): buzzer pattern, servo slew, hold expiry.
void actuatorsUpdate(uint32_t nowMs);

// Return true if applied. On refusal, *why points to a short reason string.
bool actuatorsManualFan(bool on, uint32_t nowMs, const char **why);
bool actuatorsManualWindow(float frac, uint32_t nowMs, const char **why);

// Which manual holds are active, e.g. "fan window" (empty = none). For logging.
const char *actuatorsHolds();

bool actuatorsFanOn();
float actuatorsWindowFrac();  // commanded fraction 0.0-1.0 (reported in telemetry)
bool actuatorsBuzzerOn();

// HARDWARE_TEST_MODE: call repeatedly from loop(); prints prompts on Serial.
void actuatorsHardwareTestTick();
