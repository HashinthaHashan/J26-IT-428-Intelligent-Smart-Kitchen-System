// Deterrent trials: vibration motor + LED + buzzer.
//
// A trial starts the INSTANT a trigger is confirmed (PIR, IR or vibration, after that
// sensor's own debounce): the outputs for the trial's condition switch on at once,
// with no waiting on the camera or the network. The camera photo is requested at the
// same moment in parallel; when the backend's species answer arrives it is ATTACHED
// to the trial that is already running (it never decides whether to fire).
//
// Timeline of every trial: ACTIVATION_S of motor/LED/buzzer, then OBSERVATION_S of
// watching. Safety: the motor is forced off at boot, capped at MOTOR_MAX_ON_MS, and
// the task watchdog (see .ino) resets the chip if loop() ever hangs. The buzzer follows
// the same rules: off after ACTIVATION_S, capped at BUZZER_MAX_ON_MS.
#pragma once

#include <stdint.h>
#include <string.h>

#include "config.h"

enum Condition : uint8_t {
  COND_CONTROL = 0,        // nothing fires (the experiment's control group)
  COND_VIBRATION_ONLY = 1,
  COND_LED_ONLY = 2,
  COND_VIBRATION_LED = 3,
  COND_COUNT = 4,
};

inline const char *conditionName(Condition c) {
  switch (c) {
    case COND_CONTROL: return "control";
    case COND_VIBRATION_ONLY: return "vibration_only";
    case COND_LED_ONLY: return "led_only";
    default: return "vibration_led";
  }
}

inline bool conditionFromName(const char *name, Condition &out) {
  for (int i = 0; i < COND_COUNT; i++) {
    if (strcmp(name, conditionName((Condition)i)) == 0) {
      out = (Condition)i;
      return true;
    }
  }
  return false;
}

inline bool conditionUsesMotor(Condition c) { return c == COND_VIBRATION_ONLY || c == COND_VIBRATION_LED; }
inline bool conditionUsesLed(Condition c) { return c == COND_LED_ONLY || c == COND_VIBRATION_LED; }
// The buzzer joins whichever conditions BUZZER_ON_CONDITIONS selects (config.h). The
// condition NAMES are unchanged, so stored trials keep their meaning of "which
// modalities ran" only if the mapping is recorded: see the README.
inline bool conditionUsesBuzzer(Condition c) {
  return BUZZER_ENABLED && (((BUZZER_ON_CONDITIONS) >> (int)c) & 1) != 0;
}

// The condition of the next trial. EXPERIMENT_MODE rotates
// control -> vibration_only -> led_only -> vibration_led; otherwise DEFAULT_CONDITION.
inline Condition nextDefaultCondition(uint8_t &cycleIndex) {
  if (EXPERIMENT_MODE) {
    const Condition c = (Condition)(cycleIndex % COND_COUNT);
    cycleIndex = (cycleIndex + 1) % COND_COUNT;
    return c;
  }
  Condition c = COND_VIBRATION_LED;
  conditionFromName(DEFAULT_CONDITION, c);
  return c;
}

enum DeterrentState : uint8_t { DS_IDLE = 0, DS_ACTIVATION, DS_OBSERVATION };

// A finished trial, ready to be published as a DeterrenceTrial.
struct TrialRecord {
  char trialId[40];
  char species[12];     // "" = unknown (the camera answered late, never, or said non-pest)
  char requestId[24];   // the capture request sent for this trigger ("" = none was sent)
  char condition[16];
  char zone[20];
  uint16_t activationS, observationS;
  uint32_t startEpoch;  // 0 = clock was not synced when the trial started
  uint32_t startMs;
};

void deterrentBegin();  // motor OFF, LED off (call before anything else)
void deterrentUpdate(uint32_t nowMs, bool online);

// Any confirmed trigger (PIR, IR or vibration) while idle: starts the next trial NOW,
// with its condition from the experiment cycle. `requestId` is the capture request sent
// for this trigger ("" if none could be sent); it is only used to match a late species
// answer to this trial. Returns false if a trial is already running (the trigger is
// still logged as an event by the caller).
bool deterrentStart(uint32_t nowMs, const char *zone, const char *requestId, uint32_t epoch);

// The backend's species answer for a capture request. If that request belongs to the
// trial that is still running (activation or observation), its species is recorded
// on it and true is returned. It never starts, stops or changes any output. Returns
// false if there is no such trial any more (it was already published).
bool deterrentAttachSpecies(const char *requestId, const char *species);

// Manual test: runs `c` now if idle (species unknown).
bool deterrentManual(uint32_t nowMs, Condition c, const char *zone, uint32_t epoch);

bool deterrentTakeFinished(TrialRecord &out);
DeterrentState deterrentState();
const char *deterrentStateName();
bool deterrentMotorOn();
bool deterrentBuzzerOn();
uint32_t deterrentTrialCount();

// True if the chip last reset while the motor was running (survives the reset).
bool deterrentMotorWasOnAtReset();

// HARDWARE_TEST_MODE: one step per call (motor on/off, LED on/off), with prompts.
void deterrentHardwareTestStep();

int deterrentSelfTest();
