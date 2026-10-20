# Pest detection, Board 1: sensors + deterrent (ESP32-WROOM)

PIR, IR and vibration sensors; a vibration motor, an LED and a buzzer as the deterrent. ANY of the
three sensors starts a deterrent trial **immediately** (no waiting on the camera or the network). At the
same moment it asks the backend for a camera photo; the species the camera finds is attached to the
trial afterwards, if it arrives while the trial is still running.
The camera board is separate: [`../Pest_Camera_Device/`](../Pest_Camera_Device/README.md).

Sketch folder: `Pest_Sensor_Device/` (open `Pest_Sensor_Device.ino`). Board: **ESP32 Dev Module**.

## Status: what is verified and what is not

| Item | Status |
| --- | --- |
| Compiles for ESP32 Dev Module (normal and `HARDWARE_TEST_MODE`) | Verified with Arduino CLI 1.5.1 and the installed `esp32` core 4.0.0-alpha1 |
| Whole pipeline (event, capture request, relay, photo upload, YOLO, event update, species command) | Verified end to end with `firmware/tools/pest_pipeline_check.py` playing both boards through the real broker and HTTP, using a stand-in ONNX model (about 0.5 s warm) |
| Backend logic | 31 backend tests pass, 19 of them for this pipeline |
| Debouncer / condition-cycle self-tests | Compile; they run on the board at boot (`[SELFTEST] debounce=ok deterrent-logic=ok`) |
| Sensor polarity, motor polarity, the motor under load, brownout behaviour, WiFi/MQTT on this board | **Not tested on hardware.** Use `HARDWARE_TEST_MODE` and the checklist below |
| Your trained YOLO model | **Not in the repo yet.** Drop `pest_yolo.onnx` into `ml/models/` (see `../../ml/models/README.md`) |

## Hardware and its known limits

| Part | Pin |
| --- | --- |
| IR proximity OUT/DO | GPIO27 |
| Vibration sensor OUT/DO | GPIO26 |
| PIR OUT | GPIO25 |
| Vibration-motor driver IN | GPIO33 |
| Indicator LED anode (220-330 ohm) | GPIO32 |
| Bare 2-pin **passive** buzzer: + (longer leg) | GPIO19 (driven with `tone()`, see below) |
| Bare 2-pin passive buzzer: - (shorter leg) | GND (shared rail) |

Known limitations, carried forward on purpose:

* **No ultrasonic transducer and no speaker.** The deterrent is vibration + LED + a simple buzzer. Nothing in the
  firmware, backend or app assumes ultrasonic; `ultrasonic` is rejected as a condition. A speaker with a PAM8403
  amplifier was considered for sound and **replaced by a simple buzzer** for simplicity. It is a bare 2-pin
  **passive** buzzer wired straight to a GPIO (not the active 3-pin module on the LPG board). A passive buzzer has no
  oscillator inside: a steady HIGH/LOW gives only one faint "tik", so the firmware drives it with `tone(GPIO19, 2000)`
  and `noTone()`. It makes a single steady tone: there are no recorded or tuned sounds.
* **`vib_rms_g` is a 0/1 placeholder.** The vibration sensor is digital, so the field is `1.0`
  while the sensor is active and `0.0` otherwise; it is not a real acceleration RMS.
* **`ambient_lux` is `0.0`**: this unit has no light sensor.
* **Buzzer volume is reduced (known hardware limitation, not a bug).** The buzzer works, but it is quiet because it
  is driven directly from GPIO19: an ESP32 pin cannot supply the current a passive buzzer needs for full volume.
  Confirmed by test: with the + leg connected to 5 V instead of the GPIO, the same buzzer is at full volume, so the
  buzzer is fine and only the current drive is limited. Full volume needs a **switch circuit: an NPN transistor
  (2N2222 / 2N3904 or similar) with a ~1 kOhm base resistor**, GPIO19 driving only the base and the buzzer powered
  from 5 V through the transistor. That circuit is **not fitted and not assumed anywhere**; it is a future hardware
  addition. The firmware already drives the same pin with a tone, so adding the transistor needs no code change.
  The first `HARDWARE_TEST_MODE` buzzer line says the faint volume is expected.
* **A tone started with `tone()` is hardware PWM and keeps sounding if `loop()` hangs.** The fail-safe is the same
  as for the motor: the watchdog resets the chip after `WATCHDOG_S` (8 s), which stops it. Normal operation switches
  it off after `ACTIVATION_S`, and `BUZZER_MAX_ON_MS` caps it. `BUZZER_TONE_HZ` (default 2000 Hz) is the tone; passive
  buzzers are usually loudest near their own resonance (commonly 2 to 4 kHz), so try 2500, 3000 or 4000 if you want it
  louder.
* **Polarity is not assumed** for the sensors and the motor driver: `PIR_/VIB_/IR_ACTIVE_HIGH` and `MOTOR_ACTIVE_HIGH` are in
  `config.h`; confirm each with `HARDWARE_TEST_MODE` (below). FC-51-style IR modules are often
  LOW-active.
* The PIR needs 30 to 60 s after power-up; it is ignored for the first `PIR_WARMUP_S` (45 s).

## How a trigger works

```
sensor (PIR, IR or vibration; debounced 200 ms, 8 s cooldown PER sensor)
  |-- deterrent trial STARTS NOW   condition = next of the experiment cycle (control, vibration_only,
  |                                led_only, vibration_led); outputs switch on in the same moment
  |-- capture_request {request_id, event_ts, ...}  (fire and forget)    -> .../pest-kitchen01/capture_request
  `-- PestEvent  (trigger_source "PIR"|"IR"|"Vibration")                  -> .../pest-kitchen01/event
                                         ... about a second later, if the camera and model answer ...
backend --"classification" command {species, confidence, request_id}--> this board
        -> attached to the trial that is still running (it never starts, stops or changes an output)
```

* **No waiting, no paths.** There is a single behaviour: the trial starts the instant a trigger is
  confirmed. The earlier "fast path / informed path" split no longer exists: the camera cannot delay,
  choose or cancel anything. `DeterrenceTrial.informed` was removed from the contract because it can
  no longer mean anything; whether a trial has a species is simply whether `species` is set.
* **Any sensor may start a trial, including IR.** IR on its own is weak evidence (it only says something
  is near), and an earlier version only logged it. That is deliberately overridden: missing a real pest
  matters more than an occasional wasted activation, so IR (like PIR and vibration) starts a trial.
  (`handleTrigger()` in the `.ino` carries the same note.) Which OUTPUT a trial uses, including none for
  `control`, is a separate decision made by the experiment cycle, so some real triggers still show no
  reaction by design.
* **Condition cycle.** `EXPERIMENT_MODE true` rotates control, vibration_only, led_only, vibration_led on
  successive trials; `false` always uses `DEFAULT_CONDITION`. A trigger while a trial is already running
  is still logged as an event (and still requests a photo) but does not start a second trial.
* **Species.** When the backend's answer for this trigger's `request_id` arrives while the trial is
  running (activation or observation, up to 45 s), `rat` or `cockroach` is written onto the trial and
  published with it. `non_pest` is logged but not attached (the trial contract only knows rat and
  cockroach); it stays on the event. If the answer arrives after the trial was already published (or never)
  the trial keeps `species: null` and **the answer is not lost: the backend always writes it onto the
  `PestEvent`** (`yolo_pred` / `yolo_conf`). So there are two places to look, and the event is the complete one.
* `system_verdict` stays `uncertain` (no vision confirms the exit), so every trial appears under
  "Pending reviews" in the app for a human verdict.
* **Timeline:** `ACTIVATION_S` (15 s) of motor/LED/buzzer, then `OBSERVATION_S` (30 s), then the trial is
  published. Both unchanged.
* While offline: events and trials queue (about 100 records) and are sent, back-dated, on reconnect.
  **Capture requests are never queued** (a photo request minutes old is useless): offline, the trial still
  starts at once and simply gets no species.

### Buzzer and the experiment (read before relying on trial data)

The buzzer runs inside the same trial state machine as the motor and LED: it switches on when the trial starts,
sounds for the `ACTIVATION_S` window only (continuous by default; `BUZZER_PULSE_MS` makes it pulse), and is switched
off when activation ends (`noTone()`). It is also capped at `BUZZER_MAX_ON_MS`; at boot no tone is running and the
pin is never driven with `digitalWrite`; and the task watchdog resets the chip (which stops any tone) if `loop()` hangs.

Which conditions sound it is a bitmask in `config.h` (`BUZZER_ON_CONDITIONS`, default `12`):

| Condition | motor | LED | buzzer (default) |
| --- | --- | --- | --- |
| `control` | | | |
| `vibration_only` | yes | | |
| `led_only` | | yes | **yes** |
| `vibration_led` | yes | yes | **yes** |

The condition names are unchanged, but with the default mapping **`led_only` now means light + sound**, not light
alone, so it no longer isolates the LED. Trials recorded before and after this change share the same condition names
and `DeterrenceTrial` has no field for "buzzer fired", so they cannot be told apart afterwards except by date. If
that matters for the dissertation analysis, options are: map the buzzer to `vibration_led` only (`BUZZER_ON_CONDITIONS 8`);
or add dedicated conditions (for example `buzzer_only`, `vibration_led_buzzer`) so every combination is its own
group. That is a proposal, not built: it changes the 4-condition cycle, `/cmd` validation and your analysis.

### Commands (`kitchenguard/pest/pest-kitchen01/cmd`)

Two kinds, told apart by `action`:

```json
{"device_id":"pest-kitchen01","component":"pest","action":"classification","source":"auto",
 "params":{"species":"cockroach","confidence":0.83,"request_id":"pk-3-1234"}}
```

* `classification` (from the backend, `source: "auto"`): the camera's species answer. It is only attached to
  the matching running trial; it contains no condition and cannot start or cancel anything.
* `deterrent` (`source: "manual"`): a test that runs `params.condition` now. Send one with
  `POST /api/pest/pest-kitchen01/cmd {"condition":"led_only"}`. `condition` is `control`, `vibration_only`,
  `led_only` or `vibration_led`.

## Safety behaviour

* **Motor off first.** The motor pin is latched OFF before it becomes an output, at the very top of `setup()`.
* **Hard cap:** the motor is never on longer than `MOTOR_MAX_ON_MS` (20 s), in any state.
* **Watchdog:** if `loop()` hangs for `WATCHDOG_S` (8 s) the chip resets. Add a **10 k pull-down on
  the motor driver IN** so the motor stays off while it reboots.
* **LED has two jobs.** Idle: one short blink every 3 s when online, two quick blinks when offline.
  During a trial it belongs to the experiment: it flashes only in `led_only` / `vibration_led` and is
  dark in `control` / `vibration_only` (otherwise the status blink would confound the experiment).
* **Brownout watch.** The firmware remembers (RTC memory) whether the motor was running when the
  chip last reset. If it was, the boot log says so loudly (see below).

## Power: the motor can brown the board out

This is the same failure as the two MQ sensors on the pantry board. **Tell me immediately if you
see it.** Symptoms: `[BOOT] reset reason: BROWNOUT`, the board rebooting when the motor starts, or
`[BOOT] !! The chip reset WHILE THE VIBRATION MOTOR WAS RUNNING`. The fix to apply straight away:

* power the motor driver from its **own 5 V supply** (not the ESP32's 3V3/5V pin);
* **share GND** between that supply and the ESP32;
* add a 470 uF capacitor across the motor supply and a flyback diode if the driver has none;
* 10 k pull-down from the driver IN to GND.

`HARDWARE_TEST_MODE` step 5 runs the motor and LED together for 2 s precisely to catch this.

## Setup

1. `config.h`: `WIFI_SSID` / `WIFI_PASSWORD` (**2.4 GHz only**; the ESP32 cannot see 5 GHz), `MQTT_HOST`
   (laptop IPv4 from `ipconfig`), `PEST_ZONE` (one of Sink, Pantry floor, Trash bin, Under cabinet,
   Behind fridge). Do not commit real credentials.
2. Libraries (Library Manager): **PubSubClient** (tested 2.8) and **ArduinoJson v7** (tested 7.2.1).
   Everything else ships with the ESP32 core.
3. Backend: `.\scripts\dev_stack.ps1` (broker on `0.0.0.0:1883`, API on `0.0.0.0:8000`, firewall rules; see
   `../README.md`). The pest simulator is off by default so it cannot publish as `pest-kitchen01`.

### Step 1: HARDWARE_TEST_MODE (do this before anything else)

Set `HARDWARE_TEST_MODE true`, flash, open Serial at **115200**. Every 3 s it does one step and prints a
`[TEST]` prompt: motor on, motor off, LED on, LED off, **buzzer on, buzzer off**, motor + LED + buzzer together, all off. Between steps it
prints the **raw** level of the PIR, IR and vibration pins every 0.5 s.

* Motor should run at "MOTOR ON" and stop at "MOTOR OFF". If it runs at the wrong step, flip
  `MOTOR_ACTIVE_HIGH`.
* Wave a hand at the PIR (after its warm-up), tap the vibration sensor, hold something near the IR
  sensor: the matching raw level must change. Set that sensor's `*_ACTIVE_HIGH` so the **active**
  state is what you saw (a LOW-active IR module needs `IR_ACTIVE_HIGH false`).
* **Listen for the buzzer** at `[TEST] BUZZER: on, tone(GPIO19, 2000Hz)`: a steady but **faint** tone (expected, see the
  volume limitation above), silent again at `BUZZER: off`. A single faint "tik" only means a constant level was
  applied, not a tone. If it is silent, check the wiring (the longer + leg to GPIO19, the shorter - leg to GND).
* Watch for any reset or `BROWNOUT` during the combined step (motor + LED + buzzer, 3 s).

Then set `HARDWARE_TEST_MODE false` and flash.

## What it prints

```
[DETERRENT] trial pest-kitchen01-3FA2-0 START NOW  condition=vibration_led  zone=Sink  outputs=[motor led buzzer]  camera=pk-0-2174
[   62s] TRIGGER IR  zone=Sink  trial=STARTED  camera=pk-0-2174  net=ONLINE
[MQTT] capture request pk-0-2174 sent (IR, Sink)
[MQTT] rx cmd: {"device_id":"pest-kitchen01",...,"action":"classification","params":{"species":"cockroach",...}}
[CMD] camera says cockroach (0.83) for request pk-0-2174 -> ATTACHED to the running trial
...
[DETERRENT] trial pest-kitchen01-3FA2-0 DONE  species=cockroach  (verdict: uncertain, needs review in the app)
[   80s] state=idle  PIR=0 IR=0 VIB=0  motor=off  trials=1  queued=0  net=ONLINE
```

The `[WIFI]`, `[MQTT]`, `[NET]` lines and `net=ONLINE` / `OFFLINE(wifi|mqtt)` are the same diagnostics as
the LPG and pantry boards (scan list, disconnect reasons, MQTT states in words); see `../README.md`,
"Network troubleshooting" and the restart checklist.

## Testing the backend half without the camera

With the backend running and a JPEG of your own (the model must be in `ml/models/`):

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/api/pest/pest-kitchen01/photo `
  -Headers @{ Authorization = "Bearer dev-token" } -ContentType "image/jpeg" -InFile .\cockroach.jpg
```

It saves the file, runs YOLO and returns `{label, confidence, ...}` (no event is updated without an
`X-Request-Id`). To play both boards through the full chain: `python firmware/tools/pest_pipeline_check.py`.

## Acceptance checklist

- [ ] `HARDWARE_TEST_MODE`: motor, LED and buzzer cycle correctly (you HEAR a faint steady tone at `BUZZER: on` and silence at `off`); polarity recorded in `config.h`; no brownout
- [ ] A `led_only` or `vibration_led` trial: the buzzer sounds for 15 s from the trial start (Serial: `outputs=[... buzzer]`), then stops; `control` and `vibration_only` stay silent
- [ ] Each of PIR, IR and vibration alone produces a correctly tagged event
      (`GET /api/pest/pest-kitchen01/events`, `trigger_source` `PIR` / `IR` / `Vibration`) **and starts a trial**
      (`TRIGGER ...  trial=STARTED`, then `trial ... START NOW`), with the motor/buzzer/LED responding about
      0.2 s after the sensor (its debounce), per the current condition (nothing for `control`)
- [ ] Any of the three causes a photo to appear in `uploads/pest-kitchen01/` within a couple of seconds
- [ ] With the model in place the event's `yolo_pred` / `yolo_conf` are filled in
- [ ] Camera board unplugged or no model: the trial still starts and runs exactly the same, with `species: null`
- [ ] With the camera and model: `[CMD] camera says ... ATTACHED to the running trial`, and the stored trial
      has the species (`GET /api/pest/pest-kitchen01/trials`); the event has it too (`.../events`)
- [ ] Unplug WiFi: triggers still start trials immediately (no camera, no species); reconnect and the queued events and
      trials arrive back-dated
- [ ] Both boards compile with no missing-library errors (verified here after installing PubSubClient and ArduinoJson)
- [ ] The app's Pest screen shows the real species instead of nothing

## Limitations

* MQTT is unauthenticated (dev broker); credentials live in `config.h`.
* `system_verdict` is always `uncertain`; a person reviews it in the app.
* The IR sensor is evidence of presence only, by design.
