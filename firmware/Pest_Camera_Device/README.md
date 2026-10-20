# Pest detection, Board 2: ESP32-CAM

Idle until the backend relays a capture order. Then it takes one photo, uploads it to the
backend over HTTP, and acknowledges over MQTT. The backend runs YOLO and answers the sensor
board. This board has no sensors, no link to the sensor board, and its own power and WiFi.
Sensor board: [`../Pest_Sensor_Device/`](../Pest_Sensor_Device/README.md).

Sketch folder: `Pest_Camera_Device/` (open `Pest_Camera_Device.ino`).
Board in the Arduino IDE: **AI Thinker ESP32-CAM** (PSRAM enabled; the firmware refuses to run without it).

## Status: what is verified and what is not

| Item | Status |
| --- | --- |
| Compiles for `AI Thinker ESP32-CAM`, JPEG (OV2640) and RGB565 (RHYX) variants | Verified with Arduino CLI 1.5.1, `esp32` core 4.0.0-alpha1 |
| The backend half: relay, `POST /photo`, YOLO, event update, species command, capture_done handling | Verified end to end with `firmware/tools/pest_pipeline_check.py` acting as this board (about 0.5 s warm, with a stand-in ONNX model) |
| Camera capture, JPEG/RGB565 behaviour, HTTP upload from this board, memory, latency | **Not tested on hardware** |

## How it works

```
sensor board --capture_request--> backend --capture (relay)--> THIS BOARD
THIS BOARD --HTTP POST photo--> backend (YOLO) --> PestEvent updated, deterrent command to the sensor board
THIS BOARD --capture_done--> backend
```

* **Subscribes** `kitchenguard/pest/pest-kitchen01/capture` (the backend's relay). Payload has `request_id`.
* **Uploads** to `POST http://<laptop>:8000/api/pest/pest-kitchen01/photo` with headers
  `Authorization: Bearer <API_TOKEN>`, `X-Request-Id`, `X-Image-Format: jpeg|rgb565`
  (and `X-Image-Width/Height` for rgb565). The reply carries the classification, which is logged.
* **Publishes** `kitchenguard/pest/pest-kitchen01/capture_done` with `request_id`, `upload_ok`, `image_format`,
  `bytes`, `detail` after **every** order (success, failure or skip), so the backend never waits for a photo
  that is not coming.
* Retained status + Last Will on `kitchenguard/pest/pest-kitchen01/camera_status` (the sensor board owns
  `.../status`, so the two never overwrite each other).

### Decisions, and why

1. **HTTP, not MQTT, for the image.** Confirmed: a JPEG is 30 to 60 KB (an RGB565 frame 150 KB). MQTT would
   need base64 (+33 %) inside a message far above the broker/client buffer limits, and a long publish
   delays the keep-alive. An HTTP POST streams the raw bytes and returns the classification in the reply.
2. **The backend relays the request** instead of the camera subscribing to the sensor board's topic. The
   backend must know each request anyway (to tie the later photo to the right event), so it can also log, rate-limit and drop requests, and the sensor board never needs to know a
   camera exists.
3. **The camera stays initialised but idle.** It only captures on an order. Re-initialising for every
   photo would add about a second to the time until the species is known. WiFi power-save is off for the same
   reason, so this board is not low-power; it is "idle", which is what you asked for (no continuous capture).
4. **No local queue.** If WiFi is down or the order is older than 5 s, the capture is skipped and logged;
   that trigger's trial still runs (it never waits for the camera), it just gets no species.
5. **No flash.** The built-in flash LED (GPIO4) stays off by default (`USE_FLASH_LED false`).

## Sensor variant: OV2640 vs RHYX-M21-45

Suppliers substitute the RHYX-M21-45 without notice. Boot prints the sensor ID (`PID 0x2642` = OV2640).

* **Default (`CAMERA_USE_RGB565 false`)**: OV2640, JPEG at VGA 640x480 (matches the 640 px YOLO input).
* **If you see** `camera init FAILED`, `frame is not a valid JPEG`, empty/garbled frames or out-of-memory:
  set `CAMERA_USE_RGB565 true` and re-flash. That uses RGB565 at QVGA 320x240 (the same fix as your working test
  notes). The frame is **uploaded uncompressed**: 153,600 bytes with `X-Image-Format: rgb565` plus width and height, so
  the backend can check `bytes == width*height*2` before accepting it (it rejects anything else), and converts it to
  JPEG itself. Do not raise the frame size on the RHYX.

## Setup

1. `config.h`: `WIFI_SSID` / `WIFI_PASSWORD` (**2.4 GHz only**), `MQTT_HOST` (laptop IPv4 from `ipconfig`;
   the photo upload uses the same address on port 8000), `API_TOKEN` (the backend's token, default `dev-token`).
   Do not commit real credentials.
2. **Power:** a solid 5 V supply. A weak USB port causes `BROWNOUT` resets (the boot log says so).
3. **Flashing the AI-Thinker:** it has no USB chip. Use a USB-serial adapter: 5V, GND, TX/RX crossed, **GPIO0 to
   GND** while uploading, then remove the jumper and press reset. Libraries: PubSubClient, ArduinoJson v7.
   The camera driver and HTTP client ship with the ESP32 core.
4. **Backend must be reachable from this board:** broker on `0.0.0.0:1883` **and the API on `0.0.0.0:8000`**
   (the preview stack now binds both), plus inbound firewall rules for TCP 1883 and **8000**:
   ```powershell
   # ADMIN PowerShell, once (1883 was done earlier):
   New-NetFirewallRule -DisplayName 'KitchenGuard API 8000' -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private
   ```
   `.\scripts\dev_stack.ps1 -CheckOnly` checks both and prints the fix. The network profile must be Private.
5. Put your YOLO export at `ml/models/pest_yolo.onnx` (see `../../ml/models/README.md`).

## What you see

```
[CAM] sensor detected: PID 0x2642 (0x2642 = OV2640) | format JPEG | frame size id 6
[MQTT] connected, subscribed to kitchenguard/pest/pest-kitchen01/capture, camera_status 'online' published (retained)
[NET] ONLINE: waiting for capture orders.
[MQTT] rx capture: {"request_id":"pk-0-2174",...}
[  412s] ORDER pk-0-2174: capturing...
[  413s] ORDER pk-0-2174 DONE: 38211 bytes (JPEG) | capture 180 ms + upload 410 ms | backend says: cockroach
[MQTT] capture_done pk-0-2174 published (upload OK)
[  442s] idle | photos ok=1 failed=0 skipped=0 | camera=ready | net=ONLINE | free heap 190000
```

Network diagnostics are the same as the other boards (`[WIFI]` scan list, disconnect reasons, MQTT states
in words, `net=OFFLINE(wifi|mqtt)`). 3 capture failures in a row re-initialise the camera; 6 restart the board
(upload/network failures do not count toward that).

## Where to check the result

* A new file in the backend's upload folder: `uploads/pest-kitchen01/<time>_<request id>.jpg` in the repo
  (preview stack) or the container's `PEST_UPLOAD_DIR`. The newest 200 are kept.
* The event: `GET /api/pest/pest-kitchen01/events` shows `yolo_pred`, `yolo_conf`, `camera_in_view: true`.
* The backend log: `photo ... saved to ...`, `species for ... sent to the device`.
* The app's Pest screen: the event card shows the species pill.

## Acceptance checklist

- [ ] Compiles with no missing-library errors (verified here)
- [ ] Boot shows the sensor ID, no `BROWNOUT`, `camera ready`, `ONLINE`
- [ ] A PIR/vibration trigger makes this board capture and upload within a couple of seconds
      (file appears in `uploads/pest-kitchen01/`, `ORDER ... DONE` in Serial)
- [ ] With the model in place `yolo_pred` / `yolo_conf` appear on the event
- [ ] Unplug this board's WiFi: orders are skipped and logged, and the sensor board's trial still starts and runs normally (without a species)
- [ ] After reconnect it receives orders again
- [ ] If JPEG fails on your module: `CAMERA_USE_RGB565 true` works and the backend accepts the upload

## Limitations

* The photo upload is plain HTTP with a shared token (dev setup); use HTTPS/auth before deployment.
* A single frame buffer: orders are handled one at a time, in order.
* An image of a pest in the dark may be poor without light; `USE_FLASH_LED true` is available but untested.
