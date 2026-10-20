# Smart Pantry, Board 2: ESP32-CAM (camera only)

Takes one photo every 5 minutes, computes colour features **on the chip**, and publishes
those features (not the image) over MQTT. It is the camera half of the logical device
`pantry01`; the sensor half is [`../Pantry_Sensor_Device/`](../Pantry_Sensor_Device/README.md).
The two are independent devices: separate power, separate WiFi, no shared pins, and they talk
to the backend, never to each other.

Sketch folder: `Pantry_Camera_Device/` (open `Pantry_Camera_Device.ino`).
Board in the Arduino IDE: **AI Thinker ESP32-CAM** (this enables PSRAM; the firmware refuses to
run without it).

## Status: what is verified and what is not

| Item | Status |
| --- | --- |
| Compiles for `AI Thinker ESP32-CAM` | Verified with Arduino CLI 1.5.1, `esp32` core 4.0.0-alpha1 (35% flash, 22% RAM) |
| Colour-feature maths | Compiles; on-board self-test at boot (`[SELFTEST] colour features=ok`). **Not executed off-board this time** (the test phone was disconnected) |
| Camera capture, JPEG decode, setup page, MQTT publish | **Not tested on hardware** |
| Backend storing the camera features | **Not built, on purpose: needs your decision** (see "Open decisions") |

## Decisions I made, and why

1. **Features are computed on the ESP32-CAM, not on the backend.** The AI-Thinker has 4 MB of
   PSRAM. A 320x240 frame is 150 KB as RGB565 and decodes in well under a second, so the chip
   can measure it itself. Sending a ~10 KB JPEG in base64 over MQTT would work but needs bigger
   buffers and a much larger message; a ~300 byte features message does not. It also means
   **no new backend upload endpoint is needed**, and you asked me not to add one without asking.
2. **JPEG path by default (OV2640), RGB565 as the switch (RHYX-M21-45).** See "Sensor variant".
3. **Frame size QVGA 320x240** for both variants: small enough to avoid the memory overflow you saw
   on the RHYX module, big enough for hue/brown/green percentages.
4. **A separate status topic.** This board publishes its retained online/offline (and Last
   Will) on `kitchenguard/pantry/pantry01/camera_status`, not `.../status`. The sensor board
   owns `.../status`; if both used it, either board dropping would overwrite the other's state.
   Consequence: the backend currently tracks only the sensor board as "the device".
5. **A setup web page (LAN only, no password)** at `http://<board-ip>/` showing the live view
   with the item regions drawn on it, because placing two items in fixed regions is impossible
   without seeing what the camera sees. Switch it off with `ENABLE_SETUP_WEB false`.
6. The AI-Thinker's built-in flash LED (GPIO4) is forced **off**; the scene is lit by the LED on
   the sensor board (always on while armed).

## Open decisions for you (not silently picked)

### A. Banana vs potato: two regions or one combined measurement?

The camera sees both items in one frame.

| | (a) Two fixed regions (`ROI_SPLIT true`, current default) | (b) One combined measurement (`ROI_SPLIT false`) |
| --- | --- | --- |
| How | banana must sit in the LEFT box, potato in the RIGHT box | whole frame measured once |
| Pro | genuinely per-item features: the only way the two compartments can differ | no placement constraint; no mix-up if an item moves |
| Con | the items must stay in their boxes; a nudged banana is measured as potato; needs a plain background | both items get the same numbers, so per-item freshness is lost (gas is already shared) |
| Fits the dissertation note ("freshness relies more heavily on camera features per item") | yes | no |

I built (a) as the default because only it supports per-item freshness, with (b) one config
flag away. The regions are fractions in `config.h`; use the setup page to adjust them. This is
a real trade-off, so please confirm which you want. A third option is later segmenting items by
colour (potato brown/grey vs banana yellow) so they can sit anywhere; it is not built.

### B. How camera features reach the backend

The existing `PantryTelemetry` message requires `mq3_ppm`, `mq135_ppm`, `temp_c`, `rh_pct`, which
only the sensor board has, so the camera board cannot publish it. I therefore publish a **new,
separate message** and have **not** changed the backend or `shared_schemas` (you asked to be
asked first):

```
topic   kitchenguard/pantry/pantry01/camera        (QoS 0, not retained)
{
  "schema_version": 1, "device_id": "pantry01", "ts": "2026-10-07T12:00:00Z",
  "frame_w": 320, "frame_h": 240, "roi_mode": "split",
  "items": [
    {"compartment":"banana","valid":true,"hue_mean":53.2,"brown_pct":12.5,"green_pct":0.0,"coverage_pct":61.0},
    {"compartment":"potato","valid":true,"hue_mean":28.4,"brown_pct":71.0,"green_pct":0.0,"coverage_pct":54.3}
  ]
}
```

The backend ignores unknown channels, so this is harmless today. **Proposal (needs your OK):** add a
`PantryCameraFeatures` model to `shared_schemas`, handle the `camera` channel in
`backend/app/mqtt/router.py`, store it in a `camera_pantry` collection, and copy the latest
`hue_mean`/`brown_pct`/`green_pct` of each compartment into the next `PantryTelemetry` document
(fields that already exist in the schema). The app and the future model then see them with no
other change. Alternative: an HTTP image-upload endpoint with feature extraction on the laptop;
more flexible for model training later, but heavier and not needed for this stage.

## Colour features (what is measured)

Per region: `hue_mean` (circular mean, 0 to 360 degrees; yellow banana ~50 to 60, brown ~20 to
30), `brown_pct`, `green_pct` (share of the *item* pixels), and `coverage_pct` (share of the
region that is item pixels, used to say "nothing there": below 4% the item is reported
`valid:false` with null features). "Item pixels" are the coloured ones: saturation >= 0.25 and
brightness >= 0.18, which removes a white/grey table and black shadow. **This assumes a plain
neutral background and steady lighting.** The brown/green thresholds in `config.h` are untuned
placeholders; tune them against real photos on the setup page.

## Sensor variant: OV2640 vs RHYX-M21-45

Suppliers substitute the RHYX-M21-45 for the OV2640 without notice. The firmware prints the
detected sensor ID at boot (`PID 0x2642` = OV2640) and warns if it is something else.

- **Default (`CAMERA_USE_RGB565 false`)**: OV2640, captures JPEG QVGA, decodes it on the chip.
- **If you see** `camera init FAILED`, `frame is not a valid JPEG`, empty or garbled frames, or
  out-of-memory: set `CAMERA_USE_RGB565 true` in `config.h` and re-flash. That switches to raw
  RGB565 at QVGA (no JPEG), the same fix as in your working test notes. Do **not** raise the frame
  size on the RHYX.
- If colours look swapped (yellow shows blue/purple), flip `CAMERA_RGB565_BIG_ENDIAN`.

## Setup

1. `config.h`: `WIFI_SSID`, `WIFI_PASSWORD` (2.4 GHz), `MQTT_HOST` (laptop IPv4). Don't commit credentials.
2. **Power:** a solid 5 V supply (a weak USB port causes `BROWNOUT` resets; the boot log says so).
3. **Flashing the AI-Thinker:** it has no USB chip. Use a USB-serial adapter: 5V, GND, TX/RX crossed,
   **GPIO0 to GND** while uploading, then remove it and press reset. Select the board
   `AI Thinker ESP32-CAM`. Libraries needed: PubSubClient, ArduinoJson (v7). The camera driver
   and `WebServer` ship with the ESP32 core.
4. Start the backend with `.\scripts\dev_stack.ps1` (broker on the LAN, firewall rule; see `../README.md`).
5. Open Serial Monitor at 115200. Within about 20 s you should see the sensor line, the setup
   page URL, then the first capture.
6. Open `http://<board-ip>/`, aim the camera, and place the banana in the orange box and the
   potato in the blue box on a plain background.

## What you see

```
[CAM] sensor detected: PID 0x2642 (0x2642 = OV2640) | format JPEG | 320x240
[WEB] setup page: http://192.168.8.231/   (live view with the item regions drawn on it)
[   42s] CAPTURE #0  320x240  frame 9812 bytes  mode=split  net=ONLINE
  banana: hue= 53.2 deg  brown= 12.5%  green=  0.0%  item coverage= 61.0%
  potato: hue= 28.4 deg  brown= 71.0%  green=  0.0%  item coverage= 54.3%
[MQTT] camera features published
```

Network diagnostics are the same as on the other boards (`[WIFI]` scan list, disconnect
reasons, MQTT states in words, `net=OFFLINE(wifi|mqtt)`). Captures made while offline are queued
(one hour) and published on reconnect. After 3 failed captures in a row it re-initialises the
camera; after 6 it restarts the board.

## Where to check the result

The backend does not store camera features yet (decision B), so check them here:

1. **Serial Monitor** (above).
2. **The setup page** `http://<board-ip>/` for the picture and regions.
3. **The MQTT message itself**, from the laptop: `python firmware/tools/watch_mqtt.py "kitchenguard/pantry/pantry01/camera"`.
   You should see one JSON message per capture.

## Acceptance checklist

- [ ] Board compiles with no missing-library errors (verified here)
- [ ] Boot shows the sensor ID, no `BROWNOUT`, and the setup page URL
- [ ] The setup page shows a sensible image; regions line up with the banana and potato
- [ ] A capture runs every 5 minutes; `CAPTURE #n` shows hue/brown/green per item
- [ ] `watch_mqtt.py` shows the `.../camera` message after each capture
- [ ] Unplug WiFi, wait two captures, reconnect: queued captures are published
- [ ] Decision A (regions vs combined) and decision B (backend storage) are confirmed by you

## Limitations

- Features are only as good as the lighting and background; tune thresholds on real photos.
- The setup web page has no authentication (LAN only, dev). Turn it off when done.
- MQTT is unauthenticated (dev broker).
- JPEG QVGA only; larger frames were deliberately avoided for memory and the RHYX variant.
