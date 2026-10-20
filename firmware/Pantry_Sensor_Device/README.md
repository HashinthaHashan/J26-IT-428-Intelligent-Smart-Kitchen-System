# Smart Pantry, Board 1: gas + climate sensors (regular ESP32)

Reads MQ-3 (ethanol), MQ-135 (ammonia) and a DHT22 once a minute and publishes them to
the backend as the pantry device `pantry01`. It also drives the LED that lights the scene
for the camera board. The camera board is a separate device: see
[`../Pantry_Camera_Device/README.md`](../Pantry_Camera_Device/README.md).

Sketch folder: `Pantry_Sensor_Device/` (open `Pantry_Sensor_Device.ino`). Board: **ESP32 Dev Module**.

## Status: what is verified and what is not

| Item | Status |
| --- | --- |
| Compiles for ESP32 Dev Module, normal and `CALIBRATE_MODE` builds | Verified with Arduino CLI 1.5.1 and the installed `esp32` core 4.0.0-alpha1 |
| Telemetry JSON matches the backend `PantryTelemetry` schema, field names and order | Verified by `python firmware/tools/check_contract.py` |
| Backend stores and serves both compartments, rule prediction | Verified by `backend/tests/test_pantry.py` (11 backend tests pass) |
| MQ gas curves | **Uncalibrated placeholders**: constants verified against a published library, not measured on your sensors |
| Sensor-maths self-test | Compiles; **not executed this time** (the test phone was disconnected). It runs on the board at boot: look for `[SELFTEST] sensor maths=ok` |
| Everything on real hardware (readings, WiFi, MQTT, app) | **Not tested.** Use the acceptance checklist below |

## Checked assumptions (read these, they are the ones that cost time on the LPG build)

1. **MQ-3 and MQ-135 VCC go to the ESP32 `5V`/`VIN` pin, NOT 3.3 V.** Their heater needs 5 V.
   On 3.3 V the readings pin near minimum and look like noise. The firmware prints
   `[CHECK] ... VCC must be on the 5V/VIN pin` at every boot and reports `[SENSOR FAULT] ... AO ~0 V`
   instead of publishing garbage. GND must be common with the ESP32.
2. **AO goes through the 10k/15k divider to an analog pin, not a digital pin.** MQ-3 to
   GPIO34 and MQ-135 to GPIO35 (both ADC1, input-only, work with WiFi). 5 V AO appears
   as 3.0 V at the pin, below the 3.3 V limit. `config.h` undoes the divider in software.
3. **Load resistors:** `MQ3_RL_OHM` and `MQ135_RL_OHM` default to 10 kΩ. Read the SMD marking
   on each module (`102` = 1 kΩ, `502` = 5 kΩ, `103` = 10 kΩ) and set the real values. A wrong RL
   makes every ppm wrong.
4. **Use the 2.4 GHz WiFi name**; the ESP32 cannot see 5 GHz networks.

## Shared airspace: two compartments, one reading (deliberate)

The pantry is one box holding a banana and a potato in the same air, so the gas, temperature
and humidity readings **cannot be separated per item**. The backend, database and app model
the pantry as two compartments, so each cycle the firmware publishes the **same** reading twice:

```
kitchenguard/pantry/pantry01/telemetry   {"compartment":"banana", ...same values...}
kitchenguard/pantry/pantry01/telemetry   {"compartment":"potato", ...same values...}
```

This duplication is intentional, not a bug (`mqtt_client.cpp` says so at the publish loop).
It means both compartments always get the same gas-based freshness until camera features
exist; per-item differences can only come from the camera. This matches the dissertation
note: *gas sensing is shared across compartments; freshness relies more heavily on
camera-based features per item.* All other fields (`mass_kg`, `item_count`, `hue_mean`,
`brown_pct`, `green_pct`) are `null` from this board.

## Files

```
Pantry_Sensor_Device/
  Pantry_Sensor_Device.ino   setup()/loop(): sample, warm-up, publish cycle, CALIBRATE_MODE
  config.h                   WiFi, MQTT, pins, curves, R0 placeholders, timing
  sensors.h / sensors.cpp    MQ-3 / MQ-135 / DHT22, ADC -> Rs -> ppm, self-test
  mqtt_client.h / .cpp       WiFi + MQTT task, offline queue, diagnostics, Last Will
  display.h / display.cpp    optional OLED status screen (display only)
```

## Libraries (Arduino IDE, Library Manager)

DHT sensor library (Adafruit), Adafruit Unified Sensor, **PubSubClient** (tested 2.8),
**ArduinoJson** (tested 7.2.1, use v7). The first two were already installed on this PC;
PubSubClient and ArduinoJson were not.

## How the sampling rate was chosen

60 seconds (`SAMPLE_PERIOD_S`). There is no model card in the repo to confirm a rate, but the
backend's pantry features (`backend/app/services/pantry_features.py`) assume one sample per
minute: its 6-hour delta uses 360 samples and its moving average 12 samples. Change the rate
only together with the backend. Each boot waits `WARMUP_S` (180 s) before the first publish;
during warm-up the readings are only printed.

## Setup

1. Edit `config.h`: `WIFI_SSID`, `WIFI_PASSWORD` (2.4 GHz), `MQTT_HOST` (laptop IPv4 from
   `ipconfig`), `MQ3_RL_OHM`, `MQ135_RL_OHM`. Don't commit real credentials.
2. Wire per the table below. Power MQ sensors from 5 V.
3. Backend running with the broker on the LAN: `.\scripts\dev_stack.ps1` (see
   `../README.md`). The pantry simulator is **off by default** so it cannot publish as `pantry01`.
4. Calibrate (next section), then flash with `CALIBRATE_MODE false`.

| Part | Pin |
| --- | --- |
| MQ-3 AO (via 10k/15k divider) | GPIO34 |
| MQ-135 AO (via its own 10k/15k divider) | GPIO35 |
| DHT22 data | GPIO4 |
| LED (220 Ω) | GPIO27 (always on while armed) |
| MQ-3 / MQ-135 VCC | ESP32 5V / VIN |

## Calibration (BOTH gas sensors, separately)

The curves are datasheet-approximated placeholders until you measure each sensor.

1. Complete a **48 h burn-in** with both sensors powered from 5 V.
2. Set `CALIBRATE_MODE true`, flash, open Serial Monitor at **115200**.
3. Leave the pantry box open in **clean air** for 10+ minutes.
4. Each second it prints one line per sensor: raw ADC, pin/AO millivolts, `Rs`, `Rs/RL`, a
   60-second stability figure, and `Suggested MQ3_R0_OHM = ...` / `Suggested MQ135_R0_OHM = ...`.
5. When a sensor's line reads `STABLE` (std-dev under about 2% for 60 s), copy **its own**
   suggested value into `config.h` (`MQ3_R0_OHM` and `MQ135_R0_OHM` are different numbers).
6. Set `CALIBRATE_MODE false` and flash. Sanity check: in clean air expect roughly 0.4 ppm
   ethanol and 4 ppm ammonia (`Safe`/`Fresh` in the app).

How the numbers work: `R0 = Rs_clean / clean-air ratio` (60 for MQ-3, 3.6 for MQ-135), the
convention of the MQUnifiedsensor library the curves come from. The curves are
`ppm = A * (Rs/R0)^B`, the same line as `log10(Rs/R0) = Bl + M*log10(ppm)` with `M = 1/B`
and `Bl = -log10(A)/B`:

| Sensor | A | B | Notes |
| --- | --- | --- | --- |
| MQ-3 ethanol | 0.3934 mg/L x 530.7 | -1.504 | library fit is in mg/L (ratio 1 gives 0.39, the datasheet's 0.4 mg/L point); converted at 1 mg/L ~ 530.7 ppm ethanol (25 C) |
| MQ-135 ammonia | 102.2 ppm | -2.473 | output directly in ppm |

These come from the open-source MQUnifiedsensor examples (checked against the repo), **not**
from your sensors. MQ sensors also respond to other gases and to temperature/humidity, so
treat the ppm as a relative indicator, not a lab measurement. The backend rule thresholds
(ethanol 81/108 ppm, ammonia 48/111 ppm) are literature anchors and may need re-tuning once
you see real values from your box.

## What it prints

```
[  190s] PUBLISH #0  MQ-3 ethanol=   0.44 ppm | MQ-135 ammonia=   4.30 ppm | T=26.7C RH=43.2% | queued for banana + potato | net=ONLINE
[  200s] live  MQ-3=   0.45 ppm  MQ-135=   4.31 ppm  T=26.7C RH=43.2%  net=ONLINE
```

`live` lines (every `LIVE_PRINT_S` = 10 s) are for watching only; `PUBLISH` lines are what is
sent (every 60 s). The `[WIFI]`, `[MQTT]` and `[NET]` lines use the same diagnostics as the LPG
board (scan list, disconnect reasons, MQTT state codes in words, `net=OFFLINE(wifi|mqtt)`); see
`../README.md`, "Network troubleshooting". Offline cycles are queued (about 2 hours) and sent
on reconnect. Status is retained on `kitchenguard/pantry/pantry01/status` with a Last Will.

## Acceptance checklist

- [ ] `CALIBRATE_MODE` shows stable `Rs` and a suggested R0 for MQ-3 and MQ-135, separately
- [ ] Normal mode prints a `PUBLISH` line every 60 s with sane ppm / temperature / humidity
- [ ] After a cycle, **both** compartments return data (commands below)
- [ ] Unplug WiFi for a few minutes: `net=OFFLINE(wifi)`, cycles keep being queued; reconnect and
      the queued cycles arrive (timestamps in the past are back-dated correctly)
- [ ] Both boards compile with no missing-library errors (verified here after installing PubSubClient + ArduinoJson)
- [ ] The app's Pantry screen shows live values for both banana and potato

Check the backend (replace nothing; endpoints and token are unchanged):

```powershell
$h = @{ Authorization = "Bearer dev-token" }
Invoke-RestMethod -Headers $h "http://127.0.0.1:8000/api/pantry/pantry01/latest?compartment=banana"
Invoke-RestMethod -Headers $h "http://127.0.0.1:8000/api/pantry/pantry01/latest?compartment=potato"
```

Both must return `raw` (the sensor values) and `prediction` with a sensible `freshness_score`,
`rsl_h` and `stage` (`Fresh` in clean air). To see the raw MQTT messages as they arrive:
`python firmware/tools/watch_mqtt.py "kitchenguard/pantry/#"`.

## The backend rule prediction (not a model)

Until `ml/models/pantry_models_backend.joblib` exists the backend uses a documented rule in
`backend/app/services/pantry_rules.py`, marked *RULE PLACEHOLDER - replace with
pantry_models_backend.joblib when available*. Each gas sensor maps linearly: 0 ppm = 100,
ripe anchor = 60, decomposed anchor = 0; `freshness_score` is the worse sensor. `rsl_h` is
168 h x score/100. Stages: Fresh >= 75, Ripe >= 40, Deteriorating >= 15, else Spoiled. The
backend still logs one warning at startup that the joblib is missing, then uses the rule.
When the file appears it is loaded with the same present-file check used for the LPG model.

## Limitations

- The ppm values are indicative only until both sensors are calibrated.
- Both compartments share one gas reading by design (above).
- MQTT is unauthenticated (dev broker); credentials live in `config.h`.
- The OLED shows no freshness/stage: this board never receives it (the prediction is computed
  in the backend only). Showing it would need the backend to publish it back to the board.

## OLED status display (optional, display only)

0.96" SSD1306 128x64 I2C. It only draws values the sketch already computed; sensing, the
60 s publish cadence, the offline queue, WiFi/MQTT and the LED are untouched (`display.h/.cpp`
plus three call sites in the `.ino`). Set `ENABLE_OLED false` to remove it entirely.

| OLED pin | ESP32 |
| --- | --- |
| GND | GND (shared) |
| VCC | 3V3 |
| SCL | GPIO22 |
| SDA | GPIO21 |

Libraries (Library Manager): **Adafruit SSD1306**, **Adafruit GFX Library**, and
**Adafruit BusIO** (installed automatically as a dependency). Compile-tested with 2.5.13 /
1.11.11 / 1.16.2. If the panel does not answer, set `OLED_I2C_ADDR` to `0x3D`.

```
+--------------------------------+
|PANTRY               ONLINE     |  inverted bar: WARM-UP 142s while warming; NO WIFI / NO MQTT
| MQ-3        |  MQ-135          |
| 81.2        |  48.0            |  size-2 values (ppm)
| ppm         |  ppm             |
|--------------------------------|
| T 26.7 C            RH 43 %    |
+--------------------------------+
```

It redraws exactly when a reading is taken: every `LIVE_PRINT_S` (10 s) during warm-up and
between publishes, and at each publish, with the same numbers as the Serial line. A bad MQ/DHT
reading shows a SENSOR FAULT screen. One redraw is about 25 ms of I2C on the Arduino loop task
(core 1); WiFi/MQTT run on core 0, so the network is not delayed. Boot shows a
"KitchenGuard" splash and the Serial line `[OLED] SSD1306 128x64 ready at 0x3C`.
With no panel fitted you get one `[OLED] panel not found` line and everything else runs.
