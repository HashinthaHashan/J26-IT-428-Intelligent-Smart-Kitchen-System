// =============================================================================
// KitchenGuard - Component 03 (Pest detection) - BOARD 1: sensors + deterrent
// Regular ESP32-WROOM. Everything you are expected to edit lives in this file.
// =============================================================================
#pragma once

// -----------------------------------------------------------------------------
// MODES
// -----------------------------------------------------------------------------

// true = bench test. Cycles the vibration motor and the LED on/off at boot, with
// Serial prompts, then prints the raw level of the PIR / IR / vibration pins so
// you can confirm wiring and polarity BEFORE trusting any automated logic.
#define HARDWARE_TEST_MODE false

// true = run the built-in logic self-tests at boot.
#define RUN_SELFTEST true

// -----------------------------------------------------------------------------
// NETWORK  (TODO: fill in)
// -----------------------------------------------------------------------------
// The ESP32 radio is 2.4 GHz ONLY. A network named "...5G..." will not be seen.
#define WIFI_SSID "iphone"          // TODO
#define WIFI_PASSWORD "HRhasi321$$"  // TODO

// LAN IPv4 of the laptop running the backend/broker (from `ipconfig`).
// NOT 127.0.0.1. Re-check it whenever the laptop reconnects (DHCP can change it).
#define MQTT_HOST "172.20.10.12"  // TODO
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASS ""

// -----------------------------------------------------------------------------
// IDENTITY / TOPICS (must match the backend and the app: PEST_DEVICE_ID)
// -----------------------------------------------------------------------------
#define DEVICE_ID "pest-kitchen01"
// One of: "Sink", "Pantry floor", "Trash bin", "Under cabinet", "Behind fridge"
// (the backend rejects any other value).
#define PEST_ZONE "Sink"  // TODO: where this unit is mounted

#define TOPIC_EVENT "kitchenguard/pest/" DEVICE_ID "/event"
#define TOPIC_CAPTURE_REQUEST "kitchenguard/pest/" DEVICE_ID "/capture_request"
#define TOPIC_CMD "kitchenguard/pest/" DEVICE_ID "/cmd"
#define TOPIC_STATUS "kitchenguard/pest/" DEVICE_ID "/status"
#define SCHEMA_VERSION 1

// -----------------------------------------------------------------------------
// PINS (as wired; all grounds shared with the ESP32 GND)
// -----------------------------------------------------------------------------
#define PIN_IR 27     // IR proximity sensor OUT/DO
#define PIN_VIB 26    // vibration sensor OUT/DO
#define PIN_PIR 25    // PIR OUT
#define PIN_MOTOR 33  // vibration-motor driver IN
#define PIN_LED 32    // indicator LED anode (through 220-330 ohm)
#define PIN_BUZZER 19 // bare 2-pin PASSIVE buzzer: + (longer leg) -> GPIO19, - (shorter leg) -> GND.
                      // The pin is both its power and its signal (no separate VCC wire).

// -----------------------------------------------------------------------------
// POLARITY  (NOT PROVEN: confirm with HARDWARE_TEST_MODE, then record it here)
// -----------------------------------------------------------------------------
// A level is "active" (a trigger) when the pin reads this value. PIR modules
// (HC-SR501) are HIGH on motion. SW-420-style vibration modules are usually HIGH on
// vibration. Many IR obstacle modules (FC-51) are LOW when something is near.
// HARDWARE_TEST_MODE prints the raw level: wave a hand / tap / hold something near
// and check it changes the way you expect. Verified on: ____ (date)
#define PIR_ACTIVE_HIGH true
#define VIB_ACTIVE_HIGH true
#define IR_ACTIVE_HIGH true   // FC-51 style modules are often LOW-active: set false if so

// Motor driver input: HIGH switches the motor on. Confirm in HARDWARE_TEST_MODE.
#define MOTOR_ACTIVE_HIGH true

// Buzzer: a PASSIVE buzzer has no oscillator inside, so a steady HIGH/LOW only gives one
// faint "tik". It must be fed a tone, so the firmware uses tone()/noTone() (never
// digitalWrite) on PIN_BUZZER. 2000 Hz is audible and was confirmed on this hardware.
// Passive buzzers are loudest near their own resonance (commonly 2 to 4 kHz), so if you
// want it louder, try 2500 / 3000 / 4000 here. A steady tone is also more startling than
// a pulsing one, which is why BUZZER_PULSE_MS below defaults to 0 (continuous).
// KNOWN LIMITATION: driven straight from the GPIO the volume is reduced (see README).
#define BUZZER_TONE_HZ 2000

// -----------------------------------------------------------------------------
// SENSOR TIMING
// -----------------------------------------------------------------------------
#define DEBOUNCE_MS 200          // a sensor must be active this long to count
#define COOLDOWN_MS 8000         // per sensor, after a published trigger
#define PIR_WARMUP_S 45          // HC-SR501 needs 30-60 s after power-up; PIR ignored until then
#define CAPTURE_MIN_INTERVAL_MS 5000  // never ask the camera more often than this

// -----------------------------------------------------------------------------
// DETERRENT
// -----------------------------------------------------------------------------
// A trial starts the instant any trigger (PIR, IR or vibration) is confirmed: there is
// NO waiting for the camera. The photo is requested in parallel and its species answer
// is attached to the running trial afterwards (system_verdict stays "uncertain").

#define ACTIVATION_S 15          // motor/LED ON time of a trial
#define OBSERVATION_S 30         // watch time after activation (sensors logged)
#define MOTOR_MAX_ON_MS 20000    // hard cap: the motor is never on longer than this

// Buzzer in the trial. It sounds for the trial's ACTIVATION_S window only, in the
// SAME state machine as the motor and LED, for the conditions chosen here.
// BUZZER_ON_CONDITIONS is a bitmask over the existing condition numbers:
//     bit 0 control (1)  bit 1 vibration_only (2)  bit 2 led_only (4)  bit 3 vibration_led (8)
// Default 12 = led_only + vibration_led: the buzzer accompanies the LED, as the visual
// deterrent's audible partner. Change the number to change the mapping, no code needed
// (e.g. 8 = only vibration_led, 0 = never). NOTE: this makes led_only "light + sound",
// no longer light alone; see README "Buzzer and the experiment".
#define BUZZER_ENABLED true
#define BUZZER_ON_CONDITIONS 12
#define BUZZER_PULSE_MS 0        // 0 = continuous for the whole window; else on/off this long
#define BUZZER_MAX_ON_MS 20000   // hard cap: never on longer than this, whatever the state

// true  = rotate control -> vibration_only -> led_only -> vibration_led each
//         default-cycled trial (the experiment). false = always DEFAULT_CONDITION.
#define EXPERIMENT_MODE true
#define DEFAULT_CONDITION "vibration_led"

// Task watchdog: if loop() hangs this long the chip resets and the motor pin
// returns to its safe default. ALSO fit a 10 k pull-down on the driver IN so the
// motor stays off while the chip is resetting.
#define WATCHDOG_S 8

// -----------------------------------------------------------------------------
// STATUS LED
// -----------------------------------------------------------------------------
// Idle: one short blink every 3 s when online, two quick blinks when offline.
// During a trial the LED is reserved for the experiment (flashes only for
// led_only / vibration_led, dark otherwise).
#define LED_FLASH_MS 125

// -----------------------------------------------------------------------------
// NETWORK QUEUES / RETRY
// -----------------------------------------------------------------------------
#define OUT_QUEUE_LEN 100  // events + trial records kept while offline (~2 h of activity)
#define WIFI_RETRY_MS 10000
#define MQTT_RETRY_MS 5000
