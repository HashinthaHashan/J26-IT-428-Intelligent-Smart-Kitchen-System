// =============================================================================
// KitchenGuard - Component 02 (Smart Pantry) - BOARD 1: gas + climate sensors
// Everything you are expected to edit lives in this file.
// =============================================================================
#pragma once

// -----------------------------------------------------------------------------
// MODES
// -----------------------------------------------------------------------------

// true  = Calibration mode: prints raw ADC / voltage / Rs and a SUGGESTED R0 for
//         MQ-3 and MQ-135 separately, once a second. Run in CLEAN AIR after the
//         48 h burn-in (see README). false = normal firmware.
#define CALIBRATE_MODE false

// true = run the built-in math self-tests at boot.
#define RUN_SELFTEST true

// -----------------------------------------------------------------------------
// NETWORK  (TODO: fill in)
// -----------------------------------------------------------------------------
// The ESP32 radio is 2.4 GHz ONLY. A network named "...5G..." will not be seen.
#define WIFI_SSID "YOUR_WIFI_SSID"          // TODO
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"  // TODO

// LAN IPv4 of the laptop running the backend/broker (from `ipconfig`).
// NOT 127.0.0.1. Re-check it whenever the laptop reconnects (DHCP can change it).
#define MQTT_HOST "192.168.1.100"  // TODO
#define MQTT_PORT 1883
#define MQTT_USER ""
#define MQTT_PASS ""

// -----------------------------------------------------------------------------
// IDENTITY / TOPICS
// One logical pantry device "pantry01" = this board + the ESP32-CAM board.
// -----------------------------------------------------------------------------
#define DEVICE_ID "pantry01"
#define TOPIC_TELEMETRY "kitchenguard/pantry/" DEVICE_ID "/telemetry"
#define TOPIC_STATUS "kitchenguard/pantry/" DEVICE_ID "/status"
#define SCHEMA_VERSION 1

// -----------------------------------------------------------------------------
// PINS (as wired)
// -----------------------------------------------------------------------------
#define PIN_MQ3_AO 34     // MQ-3  analog out via 10k/15k divider (ADC1, input-only)
#define PIN_MQ135_AO 35   // MQ-135 analog out via its own 10k/15k divider (ADC1, input-only)
#define PIN_DHT 4         // DHT22 data
#define PIN_LED 27        // camera-lighting LED via 220 ohm; always ON while armed

// -----------------------------------------------------------------------------
// OLED STATUS DISPLAY (optional, display only)
// -----------------------------------------------------------------------------
// 0.96" SSD1306 128x64 I2C: GND -> shared GND, VCC -> 3V3, SCL -> GPIO22, SDA -> GPIO21.
// These are the ESP32's default I2C pins; nothing else on this board uses them.
// Needs Library Manager: "Adafruit SSD1306" + "Adafruit GFX Library" (+ "Adafruit BusIO").
// With no panel fitted the firmware prints one [OLED] line and carries on normally.
#define ENABLE_OLED true
#define PIN_OLED_SDA 21
#define PIN_OLED_SCL 22
#define OLED_I2C_ADDR 0x3C  // some modules are 0x3D
#define OLED_I2C_HZ 400000
#define OLED_WIDTH 128
#define OLED_HEIGHT 64

// -----------------------------------------------------------------------------
// MQ SENSOR POWER  (CHECKED ASSUMPTION - read this)
// -----------------------------------------------------------------------------
// MQ-3 and MQ-135 need 5 V on VCC to heat their element. On 3.3 V they read
// pinned/garbage values that look like noise (this is exactly what bit the LPG
// build). Wire BOTH sensors' VCC to the ESP32 5V/VIN pin (USB-powered), never to
// 3V3. GND common with the ESP32. The firmware flags "AO ~ 0 V" at boot/run.
#define MQ_VCC_MV 5000.0f

// Divider between each AO and its ESP32 pin (GPIO tolerates 3.3 V max).
// 10k top / 15k bottom => 5 V AO appears as 3.0 V at the pin.
#define DIVIDER_R_TOP_OHM 10000.0f
#define DIVIDER_R_BOTTOM_OHM 15000.0f

// AO below this (after undoing the divider) = no signal = a FAULT, not clean air.
#define MQ_MIN_VALID_MV 100.0f

// -----------------------------------------------------------------------------
// MQ-3 (ethanol)  -  UNCALIBRATED PLACEHOLDERS
// -----------------------------------------------------------------------------
// Load resistor ON YOUR MQ-3 MODULE (SMD marking 102 = 1k, 502 = 5k, 103 = 10k).
#define MQ3_RL_OHM 10000.0f  // TODO: set to the real value

// Curve: concentration = A * (Rs/R0)^B, which is the same line as
//        log10(Rs/R0) = Bl + M*log10(ppm)   with   M = 1/B,  Bl = -log10(A_ppm)/B.
// Constants come from the open-source MQUnifiedsensor library's MQ-3 ALCOHOL fit
// (a = 0.3934, b = -1.504), verified against its published examples, NOT from a
// measurement of your sensor. That fit's output is in mg/L (a ratio of 1 gives
// 0.39, matching the datasheet's 0.4 mg/L test point), so it is converted to ppm
// of ethanol vapour with 1 mg/L ~= 530.7 ppm at 25 C.
#define MQ3_CURVE_A_MGL 0.3934f
#define MQ3_CURVE_B -1.504f
#define MQ3_MGL_TO_PPM 530.7f
// Datasheet-style clean-air ratio: Rs(clean air) / R0 ~= 60  =>  R0 = Rs_clean / 60.
#define MQ3_CLEAN_AIR_RATIO 60.0f
// TODO (REQUIRED): replace with "Suggested MQ3_R0_OHM" printed by CALIBRATE_MODE.
#define MQ3_R0_OHM 705.0f

// -----------------------------------------------------------------------------
// MQ-135 (ammonia)  -  UNCALIBRATED PLACEHOLDERS
// -----------------------------------------------------------------------------
#define MQ135_RL_OHM 10000.0f  // TODO: set to the real value on your module

// MQUnifiedsensor NH4 fit: ppm = 102.2 * (Rs/R0)^-2.473 (output already in ppm).
#define MQ135_CURVE_A 102.2f
#define MQ135_CURVE_B -2.473f
#define MQ135_CLEAN_AIR_RATIO 3.6f   // R0 = Rs_clean / 3.6
// TODO (REQUIRED): replace with "Suggested MQ135_R0_OHM" printed by CALIBRATE_MODE.
#define MQ135_R0_OHM 25876.0f

#define PPM_MIN 0.0f
#define PPM_MAX 10000.0f

// -----------------------------------------------------------------------------
// TIMING
// -----------------------------------------------------------------------------
// Pantry changes slowly: one reading every 60 s. The backend's pantry features
// assume exactly this rate (its 6 h delta uses 360 samples, its moving average
// 12 samples = 12 min), so keep 60 s unless you also change the backend.
// No model card exists in the repo to confirm it; adjustable here.
#define SAMPLE_PERIOD_S 60

// Readings during this warm-up are shown on Serial but NOT published (a cold MQ
// element reads wrongly). 48 h burn-in is a one-off; this is the per-boot warm-up.
#define WARMUP_S 180

// Serial-only live printout between publishes (0 = off), so you can watch values.
#define LIVE_PRINT_S 10

#define MQ_ADC_SAMPLES 16  // readings averaged per sensor sample

// Offline queue: one entry per 60 s cycle (each cycle = 2 MQTT messages).
#define TELEMETRY_QUEUE_LEN 120  // ~2 h of cycles while offline
#define WIFI_RETRY_MS 10000
#define MQTT_RETRY_MS 5000
