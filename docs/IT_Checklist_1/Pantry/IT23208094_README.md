# KitchenGuard – Smart Pantry Freshness Monitoring

**Project ID:** J26-IT-428  
**Project:** KitchenGuard  
**Component:** Smart Pantry Freshness Monitoring  
**Submission:** IT Checklist 1 – PP1 – Git Repository README

## 1. Component Overview

The Smart Pantry component monitors banana and potato freshness using gas, temperature, humidity, and optional camera-derived colour features. It estimates a freshness score, remaining shelf life, and one of four stages: `Fresh`, `Ripe`, `Deteriorating`, or `Spoiled`.

The component:

- measures ethanol using MQ-3 and ammonia/air-quality response using MQ-135;
- measures temperature and relative humidity with a DHT22;
- represents banana and potato as two logical compartments;
- calculates time-series features and cumulative degree-hours;
- uses an optional trained model or a documented rule fallback;
- stores current and historical predictions;
- sends real-time updates to the Flutter application; and
- optionally calculates per-item colour features on a separate ESP32-CAM.

## 2. Architecture and Data Flow

```text
MQ-3 + MQ-135 + DHT22 --> ESP32 sensor board --> MQTT telemetry
                                                        |
ESP32-CAM --> on-device colour features --> MQTT camera  |
                                                        v
                                                  FastAPI backend
                                                   |     |     |
                                                features model storage
                                                   |
                                      REST + WebSocket updates
                                                   |
                                           Flutter Pantry screen
```

The sensor board samples every 60 seconds because the backend features use a one-minute sampling assumption. The pantry is one shared airspace, so the firmware publishes the same gas and climate reading for both `banana` and `potato`. Per-item differences are intended to come from camera features.

## 3. Main Technologies

| Layer | Technology |
| --- | --- |
| Sensor device | ESP32 Dev Module, Arduino/C++ |
| Camera device | AI Thinker ESP32-CAM |
| Sensors | MQ-3, MQ-135, DHT22 |
| Optional display | SSD1306 128×64 OLED |
| Messaging | MQTT / Mosquitto |
| Backend | Python 3.11+, FastAPI, Pydantic |
| Storage | MongoDB or the in-memory preview repository |
| Prediction | Optional scikit-learn/joblib models with documented rule fallback |
| Mobile application | Flutter, Dart, Riverpod, Dio, WebSocket |
| Testing | Pytest and Flutter test |

## 4. Repository Structure

```text
firmware/Pantry_Sensor_Device/
  Pantry_Sensor_Device.ino   Sensor sampling and publish loop
  config.h                   Network, sensor curves, pins and timing
  sensors.cpp/.h             ADC, gas conversion, DHT22 and self-tests
  mqtt_client.cpp/.h         MQTT publishing and offline queue
  display.cpp/.h             Optional OLED output

firmware/Pantry_Camera_Device/
  Pantry_Camera_Device.ino   Camera capture and feature publication
  config.h                   Camera, regions, network and timing
  camera.cpp/.h              ESP32-CAM acquisition
  color_features.h           Hue, brown, green and coverage features
  mqtt_client.cpp/.h         Camera feature publishing

backend/app/services/pantry_features.py
backend/app/services/pantry_rules.py
backend/app/services/inference.py
backend/app/api/pantry.py
shared_schemas/kitchenguard_schemas/pantry.py
simulators/pantry_sim.py
frontend/lib/features/pantry/
frontend/lib/models/pantry.dart
backend/tests/test_pantry.py
frontend/test/pantry_screen_test.dart
```

## 5. Telemetry and Feature Engineering

The sensor device publishes to:

```text
kitchenguard/pantry/pantry01/telemetry
```

The schema includes:

- `device_id`, `compartment`, and timestamp;
- MQ-3 and MQ-135 ppm values;
- temperature and relative humidity;
- optional mass and item count; and
- optional hue, brown-pixel, and green-pixel features.

The backend calculates normalized gas features, six-hour changes, 12-sample moving averages, 24-sample climate moving averages, and cumulative degree-hours above 13 °C.

The optional camera board publishes lightweight features rather than full images:

```text
kitchenguard/pantry/pantry01/camera
```

It can calculate `hue_mean`, `brown_pct`, `green_pct`, and item coverage for fixed banana and potato regions. The current backend telemetry pipeline does not yet merge this separate camera-channel message into pantry predictions; gas/climate telemetry remains the implemented prediction input.

## 6. Freshness Prediction

If `ml/models/pantry_models_backend.joblib` is present, the backend loads compartment-specific trained models. If it is absent, the system continues with the documented fallback in `backend/app/services/pantry_rules.py`.

The fallback uses these literature anchors:

| Sensor | Ripe anchor | Decomposed anchor |
| --- | ---: | ---: |
| MQ-3 ethanol | 81 ppm | 108 ppm |
| MQ-135 ammonia | 48 ppm | 111 ppm |

Each sensor score decreases from 100 at 0 ppm, through 60 at its ripe anchor, to 0 at its decomposed anchor. The final freshness score is the worse of the two sensor scores. Remaining shelf life is estimated as:

```text
remaining shelf life = 168 hours × freshness score / 100
```

| Freshness score | Stage |
| --- | --- |
| 75–100 | Fresh |
| 40–74.99 | Ripe |
| 15–39.99 | Deteriorating |
| Below 15 | Spoiled |

This fallback supports integration and demonstration; it is explicitly not presented as a trained research model.

## 7. REST and Live Interfaces

All `/api` requests require `Authorization: Bearer dev-token` in the development environment.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/pantry/{device_id}/latest?compartment=banana` | Latest result for one compartment |
| `GET` | `/api/pantry/{device_id}/history?compartment=banana&minutes=1440` | Compartment history, newest first |
| `WS` | `/ws/live` | Live pantry and alert frames |

## 8. Running the Component Without Hardware

From the repository root:

```powershell
python -m pip install -r .\backend\requirements.txt
python -m pip install amqtt==0.12.1
python .\backend\preview_stack.py
```

The included simulator generates banana and potato telemetry. Verify it using:

```powershell
$headers = @{ Authorization = "Bearer dev-token" }
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pantry/pantry-banana01/latest?compartment=banana"
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pantry/pantry-potato01/latest?compartment=potato"
```

The physical firmware uses the single device ID `pantry01` and publishes both compartments under that ID. Therefore, physical-device checks use:

```powershell
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pantry/pantry01/latest?compartment=banana"
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pantry/pantry01/latest?compartment=potato"
```

## 9. Running the Sensor Board

1. Open `firmware/Pantry_Sensor_Device/Pantry_Sensor_Device.ino` for an ESP32 Dev Module.
2. Install Adafruit DHT Sensor, Adafruit Unified Sensor, PubSubClient, and ArduinoJson v7.
3. Set Wi-Fi and MQTT values in `config.h`; use 2.4 GHz Wi-Fi and the backend computer's LAN IPv4 address.
4. Power each MQ sensor from 5 V and use a separate 10 kΩ/15 kΩ divider for its analog output.
5. Connect MQ-3 AO to GPIO34, MQ-135 AO to GPIO35, DHT22 data to GPIO4, and the scene LED to GPIO27.
6. Confirm the real load-resistor values on both modules.
7. After burn-in, calibrate the sensors independently using `CALIBRATE_MODE`, save each suggested R0 value, and return to normal mode.
8. Flash the firmware and monitor serial output at 115200 baud.

An optional SSD1306 OLED can show local sensor and network status. It is display-only; prediction is performed in the backend.

## 10. Running the Camera Board

1. Open `firmware/Pantry_Camera_Device/Pantry_Camera_Device.ino` and select AI Thinker ESP32-CAM.
2. Configure Wi-Fi, MQTT, camera format, and banana/potato regions in `config.h`.
3. Use a stable 5 V supply and PSRAM-capable board configuration.
4. Place the banana in the configured left region and potato in the right region against a plain background.
5. Use the board's local setup page to inspect and adjust the regions.
6. For an OV2640 use the default JPEG path; use the documented RGB565 option if the substituted camera module requires it.

## 11. Mobile Application

The Flutter Pantry screen provides:

- banana/potato segmented selection;
- freshness percentage and stage;
- remaining shelf-life countdown;
- MQ-3 and MQ-135 values;
- temperature and humidity; and
- standard loading, empty, retry, and offline states.

REST provides the initial state and WebSocket events provide live updates.

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

Relevant tests cover the literature anchors, freshness calculation, stage boundaries, independent compartment storage, spoiled-item alerts, history ordering, authenticated API routes, schema validation, model deserialization, and Pantry screen rendering.

## 13. Current Limitations

- MQ gas sensors require individual burn-in, calibration, and later threshold validation with collected data.
- MQ sensors are cross-sensitive; their ppm readings are indicative rather than laboratory measurements.
- Banana and potato currently share one gas/climate reading because they share one airspace.
- Camera feature publication exists in firmware, but backend merging of the separate camera message is not yet implemented.
- The fallback freshness calculation is a transparent integration rule, not a trained model.
- In-memory feature history resets when the backend restarts.
- Development MQTT and API security must be replaced with authenticated, encrypted production configuration.

