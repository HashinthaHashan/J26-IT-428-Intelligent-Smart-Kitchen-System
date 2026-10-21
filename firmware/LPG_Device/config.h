// =============================================================================
// KitchenGuard - Component 01 (LPG) - configuration
// Everything you are expected to edit lives in this file.
// =============================================================================
#pragma once

// -----------------------------------------------------------------------------
// MODES (set at most ONE of the test modes to true; all false = normal run)
// -----------------------------------------------------------------------------

// true  = Calibration mode. Skips everything except sensing and prints Rs / R0
//         values once a second. Run in CLEAN AIR after the 48 h burn-in.
//         See README.md "Calibration" and the R0 note further down.
// false = Normal firmware.
#define CALIBRATE_MODE false

// true  = Hardware bench test. Toggles the relay, sweeps the servo and beeps the
//         buzzer on a slow loop with Serial prompts, so you can confirm relay
//         polarity and servo direction BEFORE trusting the safety logic.
#define HARDWARE_TEST_MODE false

// true  = Run the built-in math self-tests at boot (feature maths, ppm curve,
//         debouncer). Results are printed on Serial. Cheap, leave on while
//         commissioning.
#define RUN_SELFTEST true

// DEBUG ONLY. -1 = off (normal: real MQ-2 reading). Any value >= 0 REPLACES the
// sensor ppm so you can exercise the tiers on the bench without gas:
//    350 -> Dangerous (fan on, window 45%, buzzer pulsing)
//    800 -> Critical  (fan on, window 90%, buzzer continuous, manual OFF refused)
// The sensor is ignored while this is set and telemetry carries the fake value, so
// the firmware prints a warning at boot and tags every line. ALWAYS set back to -1.
#define DEBUG_FORCE_PPM -1

// -----------------------------------------------------------------------------
// NETWORK  (TODO: fill in)
// -----------------------------------------------------------------------------
#define WIFI_SSID "iphone"          // TODO
#define WIFI_PASSWORD "HRhasi321$$"  // TODO

// IP of the machine running Mosquitto (docker compose) on your LAN.
// NOT 127.0.0.1 - that would be the ESP32 itself.
#define MQTT_HOST "172.20.10.12"  // TODO
#define MQTT_PORT 1883
#define MQTT_USER ""  // empty = anonymous (dev broker allows anonymous)
#define MQTT_PASS ""

// -----------------------------------------------------------------------------
// IDENTITY / TOPICS  (must match the backend + app: LPG_DEVICE_ID = lpg01)
// -----------------------------------------------------------------------------
#define DEVICE_ID "lpg01"
#define TOPIC_TELEMETRY "kitchenguard/lpg/" DEVICE_ID "/telemetry"
#define TOPIC_CMD "kitchenguard/lpg/" DEVICE_ID "/cmd"
#define TOPIC_STATUS "kitchenguard/lpg/" DEVICE_ID "/status"
#define SCHEMA_VERSION 1

// -----------------------------------------------------------------------------
// PINS (unchanged from your working prototype, except the gas sensor)
// -----------------------------------------------------------------------------
#define PIN_MQ2_AO 34   // MQ-2 analog out, ADC1_CH6 (input-only pin, safe with WiFi)
#define PIN_DHT 4       // DHT22 data
#define PIN_RELAY 23    // fan relay signal
#define PIN_SERVO 13    // MG996R signal (servo has its OWN 5-6 V supply, common GND)
#define PIN_BUZZER 27   // active buzzer

// -----------------------------------------------------------------------------
// RELAY POLARITY
// -----------------------------------------------------------------------------
// Evidence from your old sketch: it drove the pin LOW to switch the fan ON and
// released the pin (INPUT, pulled up by the module) to switch it OFF. That is the
// behaviour of an ACTIVE-LOW module, so this defaults to true.
// >>> THIS IS NOT PROVEN. Run HARDWARE_TEST_MODE and confirm, then record the
// >>> result here:  active-LOW confirmed on: ____ (date)
#define RELAY_ACTIVE_LOW true

// -----------------------------------------------------------------------------
// SERVO (window flap)
// -----------------------------------------------------------------------------
// Convention used by the firmware: 0 deg = CLOSED, 90 deg = FULLY OPEN.
// Your old sketch wrote 90 on gas and 0 on normal, which IS consistent with that
// convention (it only looked inverted). It also parked the servo at 90 (open) on
// boot; this firmware parks it CLOSED. Confirm the direction on the real flap with
// HARDWARE_TEST_MODE. If the flap moves the wrong way, swap the two values below.
#define SERVO_CLOSED_DEG 0
#define SERVO_OPEN_DEG 90
#define SERVO_MIN_US 500    // MG996R typical pulse range
#define SERVO_MAX_US 2400
#define SERVO_SLEW_DEG_PER_S 90.0f  // limits current surge; flap fully opens in ~1 s

// -----------------------------------------------------------------------------
// BUZZER
// -----------------------------------------------------------------------------
#define BUZZER_ACTIVE_HIGH true  // HIGH = sounding (as in your prototype)
#define BUZZER_PULSE_MS 500      // Dangerous tier: 500 ms on / 500 ms off

// -----------------------------------------------------------------------------
// MQ-2 ANALOG FRONT END  (TODO: set to your real hardware)
// -----------------------------------------------------------------------------
// MQ-2 module circuit:  Vcc --[ Rs ]--+--[ RL ]-- GND,   AO is the '+' node.
//   AO volts = Vcc * RL / (Rs + RL)   =>   Rs = RL * (Vcc - AO) / AO
#define MQ2_VCC_MV 5000.0f   // sensor supply voltage in millivolts
#define MQ2_RL_OHM 1000.0f   // TODO: load resistor ON YOUR MODULE (often 5k, some boards 1k or 10k).
                             //       Read the SMD marking (502 = 5k, 102 = 1k, 103 = 10k).

// Voltage divider between AO and GPIO34 (ESP32 pins tolerate 3.3 V max!).
//   AO --[ R_TOP ]--+--[ R_BOTTOM ]-- GND ,  GPIO34 reads the middle node.
#define DIVIDER_R_TOP_OHM 10000.0f     // TODO: your real top resistor
#define DIVIDER_R_BOTTOM_OHM 20000.0f  // TODO: your real bottom resistor

// If AO reads below this (after the divider is undone) the sensor is considered
// unpowered/disconnected: a FAULT, not "clean air".
#define MQ2_MIN_VALID_MV 100.0f

// -----------------------------------------------------------------------------
// MQ-2 CALIBRATION CONSTANTS
// -----------------------------------------------------------------------------
// Datasheet LPG curve you specified:  log10(Rs/R0) = 1.27 - 0.46 * log10(ppm)
#define MQ2_CURVE_A 1.27f
#define MQ2_CURVE_B 0.46f

// IMPORTANT: with this curve R0 is the sensor resistance at ~577 ppm (ratio 1.0),
// NOT the raw clean-air resistance. In clean air the datasheet ratio Rs/R0 is
// about 9.8. If you stored the raw clean-air Rs as R0, clean air would read ~577
// ppm and the fan would run all the time. CALIBRATE_MODE therefore prints the
// ready-to-paste value  R0 = Rs_cleanair / MQ2_CLEAN_AIR_RATIO.
#define MQ2_CLEAN_AIR_RATIO 9.8f

// TODO (REQUIRED): replace with the "Suggested MQ2_R0_OHM" printed by
// CALIBRATE_MODE for YOUR sensor. 10000 is only a placeholder so it compiles;
// ppm values are NOT trustworthy until you replace it.
#define MQ2_R0_OHM 2274.0f

#define PPM_MIN 0.0f
#define PPM_MAX 10000.0f  // MQ-2 datasheet range ends at 10000 ppm

// -----------------------------------------------------------------------------
// SAFETY / TIERS  (same thresholds as the backend rule fallback)
// -----------------------------------------------------------------------------
#define TIER_WARNING_PPM 150.0f
#define TIER_DANGEROUS_PPM 300.0f
#define TIER_CRITICAL_PPM 700.0f  // HARD OVERRIDE: >= this is Critical, instantly
// Leaving Critical needs ppm to fall to/below this (10% hysteresis) as well as the
// 3 s debounce, so the fan does not chatter around 700 ppm.
#define OVERRIDE_CLEAR_PPM 630.0f

#define DEBOUNCE_SECONDS 3  // consecutive 1 Hz readings needed to change tier

// Actuation per tier
#define WINDOW_FRAC_DANGEROUS 0.45f
#define WINDOW_FRAC_CRITICAL 0.90f

// A manual command is held until the debounced tier changes or this many seconds pass.
#define MANUAL_HOLD_S 900

// -----------------------------------------------------------------------------
// TIMING
// -----------------------------------------------------------------------------
// The trained model's features assume exactly 1 Hz. Do not change.
#define SAMPLE_PERIOD_MS 1000
#define MQ2_ADC_SAMPLES 16  // averaged per reading to tame ADC noise
// MQ-2 heater warm-up. Serial marks readings in this window "WARMUP" because a
// cold sensor can read wrongly. The 700 ppm override stays ACTIVE regardless:
// safety first, a false alarm is better than a missed one.
#define WARMUP_S 30

// -----------------------------------------------------------------------------
// NETWORK QUEUES / RETRY
// -----------------------------------------------------------------------------
#define TELEMETRY_QUEUE_LEN 120  // ~2 minutes of samples kept while offline
#define WIFI_RETRY_MS 10000
#define MQTT_RETRY_MS 5000
