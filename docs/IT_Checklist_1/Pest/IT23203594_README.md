# KitchenGuard – Pest Detection and Smart Deterrence

**Project ID:** J26-IT-428  
**Project:** KitchenGuard  
**Component:** Pest Detection and Smart Deterrence  
**Submission:** IT Checklist 1 – PP1 – Git Repository README

## 1. Component Overview

The Pest component detects possible kitchen pest activity, captures a photograph on demand, classifies visible pests, and evaluates several non-chemical deterrent conditions. It uses separate ESP32 sensor and ESP32-CAM boards so detection and deterrence can continue without waiting for image inference.

The component:

- monitors PIR motion, infrared proximity, vibration, and ambient light;
- creates an event immediately after a confirmed trigger;
- starts a deterrence trial without waiting for the camera or backend;
- requests a single camera capture for the event;
- uploads JPEG or RGB565 image data to the backend;
- optionally classifies `rat`, `cockroach`, or `non_pest` using an ONNX YOLO model;
- records system and manual trial verdicts; and
- shows event history and pending reviews in the Flutter application.

## 2. Architecture and Data Flow

```text
PIR / IR / vibration / light
            |
            v
ESP32 sensor board --> event + capture_request --> MQTT --> FastAPI
       |                                             |
       +--> immediate deterrence trial               +--> capture order
                                                            |
                                                            v
                                                        ESP32-CAM
                                                            |
                                              HTTP photo upload (raw bytes)
                                                            |
                                                            v
                                                   YOLO ONNX inference
                                                    |             |
                                           update PestEvent   classification cmd
                                                    |             |
                                                    +------> sensor board
                                                    |
                                      REST + WebSocket --> Flutter app
```

The sensor board starts the selected trial as soon as a trigger is confirmed. The image pipeline runs in parallel. A delayed or unavailable classification can leave the trial species unknown, but it never prevents the deterrent from operating.

## 3. Main Technologies

| Layer | Technology |
| --- | --- |
| Sensor/deterrent device | ESP32 Dev Module, Arduino/C++ |
| Camera device | AI Thinker ESP32-CAM |
| Sensors | PIR, IR proximity, vibration sensor, ambient light input |
| Deterrents | Vibration motor, LED and optional buzzer combinations |
| Messaging | MQTT / Mosquitto |
| Image transport | Authenticated development HTTP POST |
| Backend | Python 3.11+, FastAPI, Pydantic |
| Vision inference | ONNX Runtime, NumPy, Pillow, YOLO-compatible ONNX export |
| Storage | MongoDB or the in-memory preview repository; bounded local photo folder |
| Mobile application | Flutter, Dart, Riverpod, Dio, WebSocket |
| Testing | Pytest and Flutter test |

## 4. Repository Structure

```text
firmware/Pest_Sensor_Device/
  Pest_Sensor_Device.ino   Detection and trial state machine
  config.h                 Pins, triggers, timing and trial settings
  sensors.cpp/.h           PIR, IR, vibration and light acquisition
  deterrent.cpp/.h         Motor, LED and buzzer conditions
  mqtt_client.cpp/.h       Events, capture requests, commands and status

firmware/Pest_Camera_Device/
  Pest_Camera_Device.ino   Capture-order and upload loop
  config.h                 Camera, API, network and format settings
  camera.cpp/.h             JPEG/RGB565 capture handling
  mqtt_client.cpp/.h        Capture request and completion messages

backend/app/services/pest_pipeline.py  Request/photo/event coordination
backend/app/services/pest_yolo.py      ONNX loading and YOLO post-processing
backend/app/services/pest_logic.py     Warning decision
backend/app/api/pest.py                Events, trials, reviews and uploads
shared_schemas/kitchenguard_schemas/pest.py
simulators/pest_sim.py
frontend/lib/features/pest/
frontend/lib/models/pest.dart
backend/tests/test_pest_pipeline.py
frontend/test/pest_screen_test.dart
```

## 5. Detection, Capture and Classification

The logical device ID is `pest-kitchen01`. Main MQTT topics are:

| Topic | Direction | Purpose |
| --- | --- | --- |
| `kitchenguard/pest/pest-kitchen01/event` | Sensor → backend | Pest event |
| `.../capture_request` | Sensor → backend | Request associated with an event |
| `.../capture` | Backend → camera | Relayed capture order |
| `.../capture_done` | Camera → backend | Upload success/failure acknowledgement |
| `.../cmd` | Backend → sensor | Classification or manual deterrent command |
| `.../status` | Sensor → backend | Retained sensor-board status |
| `.../camera_status` | Camera → backend | Retained camera-board status |

A pest event includes the zone, trigger source, PIR state, vibration measurement and trigger state, ambient light, camera visibility, optional YOLO label, and confidence.

The camera uploads raw bytes to:

```text
POST /api/pest/pest-kitchen01/photo
```

The request includes `Authorization`, `X-Request-Id`, and `X-Image-Format` headers. RGB565 uploads also include width and height. The backend validates the image, converts RGB565 to JPEG when required, saves it, and correlates it with the triggering event.

If `ml/models/pest_yolo.onnx` and ONNX Runtime are available, the detector supports common YOLOv5, YOLOv8/YOLO11, and end-to-end exported output layouts. Labels are normalized to `rat`, `cockroach`, and `non_pest`. A rat or cockroach event becomes a warning when confidence is at least 0.60. If the model is missing, the backend remains operational: photos are retained but no species classification is produced.

## 6. Deterrence Experiment

The system supports four conditions:

| Condition | Output combination |
| --- | --- |
| `control` | No active deterrent |
| `vibration_only` | Vibration motor |
| `led_only` | LED, with buzzer behaviour configurable in firmware |
| `vibration_led` | Vibration motor and LED, with configurable buzzer |

Each trial can record the condition, zone, optional species, activation duration, observation window, whether the pest exited, time to leave, system verdict, and manual verdict. The mobile user can review a pending trial as `left` or `remains`.

## 7. REST and Live Interfaces

All `/api` requests require `Authorization: Bearer dev-token` in the development environment.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/pest/{device_id}/events?limit=50` | Recent pest events |
| `GET` | `/api/pest/{device_id}/trials?limit=50` | Recent deterrence trials |
| `POST` | `/api/pest/{device_id}/trials/{trial_id}/review` | Store a manual verdict |
| `POST` | `/api/pest/{device_id}/cmd` | Start a selected manual trial |
| `POST` | `/api/pest/{device_id}/photo` | Receive a camera image |
| `WS` | `/ws/live` | Live events, updates, trials, and alerts |

Example manual deterrent command:

```json
{
  "condition": "vibration_led"
}
```

## 8. Running the Component Without Hardware

From the repository root:

```powershell
python -m pip install -r .\backend\requirements.txt
python -m pip install amqtt==0.12.1
python .\backend\preview_stack.py
```

Verify generated events and trials:

```powershell
$headers = @{ Authorization = "Bearer dev-token" }
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pest/pest-kitchen01/events?limit=50"
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pest/pest-kitchen01/trials?limit=50"
```

To enable real inference, place the exported model at `ml/models/pest_yolo.onnx`. The backend logs a clear non-fatal warning if the model or ONNX Runtime is unavailable.

## 9. Running the Sensor and Deterrent Board

1. Open `firmware/Pest_Sensor_Device/Pest_Sensor_Device.ino` for an ESP32 Dev Module.
2. Install PubSubClient and ArduinoJson v7.
3. Configure 2.4 GHz Wi-Fi and the backend computer's LAN IPv4 MQTT host in `config.h`.
4. Connect sensors and outputs using the pin definitions in `config.h`; defaults include vibration input GPIO26, PIR GPIO25, and motor driver input GPIO33.
5. Confirm each sensor's active-high/active-low setting on the physical module.
6. Use hardware-test mode to verify the motor, LED, buzzer, PIR, IR, and vibration inputs.
7. Return to normal mode, flash the device, and monitor serial output at 115200 baud.
8. Allow the PIR warm-up interval before judging motion detection.

The vibration motor must use a suitable transistor/MOSFET driver and flyback protection rather than being powered directly from an ESP32 GPIO.

## 10. Running the Camera Board

1. Open `firmware/Pest_Camera_Device/Pest_Camera_Device.ino` and select AI Thinker ESP32-CAM.
2. Configure Wi-Fi, MQTT host, API token, camera format, and backend port in `config.h`.
3. Use a stable 5 V supply and configure firewall access to MQTT port 1883 and API port 8000 on the private LAN.
4. Flash using a USB-to-serial adapter with GPIO0 grounded during upload; remove the jumper and reset afterwards.
5. Use JPEG/VGA for a compatible OV2640. If the module produces invalid JPEG data, use the documented RGB565/QVGA configuration.
6. Confirm that the board subscribes to the capture topic and publishes `camera_status` online.

The camera captures only on a backend order. Images are sent through HTTP rather than MQTT to avoid base64 overhead and MQTT buffer limitations.

## 11. Mobile Application

The Flutter Pest screen provides:

- zone filtering;
- detection history with trigger and confidence details;
- rat, cockroach, non-pest, and unknown states;
- pending deterrence-trial reviews;
- `Left` and `Remains` manual verdict actions; and
- live updates and warning presentation.

## 12. Testing

Run backend tests:

```powershell
python -m pytest backend/tests -q
```

Run Flutter checks from `frontend`:

```powershell
flutter test
flutter analyze
```

The pest test suite covers label normalization, YOLO output decoding, class-aware non-maximum suppression, model loading and missing-model behaviour, capture relay, event correlation, low-confidence handling, early/late photo ordering, JPEG and RGB565 validation, upload failure acknowledgement, trial storage, manual commands, authenticated APIs, and Pest screen behaviour.

## 13. Data Handling and Current Limitations

- Uploaded photos are stored under `uploads/{device_id}`; the newest 200 per device are kept by default.
- The development upload uses plain HTTP and a shared token. Production requires HTTPS, stronger authentication, and explicit privacy/retention controls.
- Classification requires a suitable trained ONNX model and representative pest-image dataset.
- Poor lighting, occlusion, camera placement, and visually similar non-pests can reduce accuracy.
- The current warning confidence threshold is 0.60 and must be validated experimentally.
- Camera orders are processed one at a time, and the camera does not queue missed captures while offline.
- A trial may correctly remain species-unknown when no image arrives or confidence is insufficient.
- The development MQTT broker is unauthenticated and must not be exposed as a production configuration.

