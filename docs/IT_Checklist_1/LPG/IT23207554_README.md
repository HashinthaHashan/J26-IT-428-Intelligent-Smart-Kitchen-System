# KitchenGuard – LPG Leak Detection and Response

**Project ID:** J26-IT-428  
**Project:** KitchenGuard  
**Component:** LPG Leak Detection and Response  
**Submission:** IT Checklist 1 – PP1 – Git Repository README

## 1. Component Overview

The LPG component continuously monitors kitchen gas concentration using an ESP32 and an MQ-2 sensor. It combines edge-side safety logic with backend prediction so that essential safety actions continue even when Wi-Fi, MQTT, or the backend is unavailable.

The component:

- reads LPG concentration, temperature, and relative humidity;
- calculates short- and long-window gas features;
- classifies the situation as `Safe`, `Warning`, `Dangerous`, or `Critical`;
- automatically controls an exhaust fan, window servo, and buzzer;
- sends telemetry through MQTT to the FastAPI backend;
- stores readings and predictions for history and analysis;
- streams live updates to the Flutter mobile application; and
- accepts manual fan and window commands when the active safety tier permits them.

## 2. Architecture and Data Flow

```text
MQ-2 + DHT22
      |
      v
ESP32 edge feature extraction and safety classification
      |                         |
      |                         +--> fan / servo / buzzer
      v
MQTT broker --> FastAPI --> MongoDB/in-memory repository
                         |--> REST API
                         +--> WebSocket --> Flutter LPG screen

Flutter manual command --> FastAPI --> MQTT command --> ESP32 actuator
```

The edge device samples once per second. Network communication runs independently from sensing, so loss of connectivity does not stop classification or actuator control. A gas reading at or above 700 ppm always produces the `Critical` tier through a hard safety override.

## 3. Main Technologies

| Layer | Technology |
| --- | --- |
| Embedded device | ESP32 Dev Kit, Arduino/C++ |
| Sensors | MQ-2 gas sensor, DHT22 temperature/humidity sensor |
| Actuators | Relay-controlled exhaust fan, MG996R servo, active buzzer |
| Messaging | MQTT / Mosquitto |
| Backend | Python 3.11+, FastAPI, Pydantic |
| Storage | MongoDB or the in-memory preview repository |
| Prediction | Optional scikit-learn/joblib Random Forest with safe rule fallback |
| Mobile application | Flutter, Dart, Riverpod, Dio, WebSocket |
| Testing | Pytest and Flutter test |

## 4. Repository Structure

```text
firmware/LPG_Device/
  LPG_Device.ino          Main sensing, classification and control loop
  config.h                Network, pins, calibration and safety thresholds
  sensors.cpp/.h          MQ-2 and DHT22 acquisition
  features.cpp/.h         Edge feature calculation
  tier_logic.h            Tier rules, debounce and critical override
  model.h                 Optional trained model and rule fallback
  actuators.cpp/.h        Fan, window and buzzer control
  mqtt_client.cpp/.h      MQTT telemetry, commands and offline queue

backend/app/services/lpg_features.py   Backend feature calculation
backend/app/services/inference.py      Model loading and LPG prediction
backend/app/api/lpg.py                 LPG REST endpoints
shared_schemas/kitchenguard_schemas/lpg.py
simulators/lpg_sim.py
frontend/lib/features/lpg/
frontend/lib/models/lpg.dart
backend/tests/test_features.py
frontend/test/lpg_command_test.dart
```

## 5. Telemetry and Prediction

The device publishes telemetry to:

```text
kitchenguard/lpg/lpg01/telemetry
```

Commands are received from:

```text
kitchenguard/lpg/lpg01/cmd
```

Each telemetry message contains the device ID, timestamp, sequence number, raw gas ppm, temperature, humidity, fan state, window position, edge tier, and offline-mode state. The backend calculates these seven features:

| Feature | Meaning |
| --- | --- |
| `ppm_comp` | Current compensated gas value; currently equal to raw ppm pending environmental calibration |
| `d_ppm_5s` | Five-second ppm change rate |
| `slope_30s` | Thirty-second ppm slope |
| `ma10` | Ten-sample moving average |
| `ma30` | Thirty-sample moving average |
| `d_rh_10s` | Ten-second humidity change rate |
| `tt700_s` | Estimated seconds until 700 ppm |

If `ml/models/lpg_rf_backend.joblib` is present, the backend uses the trained model. Otherwise, it uses the documented fallback:

| Gas concentration | Tier |
| --- | --- |
| Below 150 ppm | Safe |
| 150–299.99 ppm | Warning |
| 300–699.99 ppm | Dangerous |
| 700 ppm or above | Critical hard override |

The edge firmware applies the same thresholds when an embedded model is unavailable. Tier changes are debounced, while entry to the 700 ppm critical state is immediate.

## 6. REST and Live Interfaces

All `/api` requests require `Authorization: Bearer dev-token` in the development environment.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/api/lpg/{device_id}/latest` | Retrieve the latest reading and prediction |
| `GET` | `/api/lpg/{device_id}/history?minutes=60` | Retrieve recent LPG history |
| `POST` | `/api/lpg/{device_id}/cmd` | Send a fan or window command |
| `WS` | `/ws/live` | Receive live LPG and alert frames |

Example manual fan command body:

```json
{
  "action": "fan",
  "value": 1
}
```

## 7. Running the Component Without Hardware

From the repository root, install backend dependencies:

```powershell
python -m pip install -r .\backend\requirements.txt
python -m pip install amqtt==0.12.1
```

Start the embedded development broker, backend, in-memory database, and all simulators:

```powershell
python .\backend\preview_stack.py
```

Verify the LPG API:

```powershell
$headers = @{ Authorization = "Bearer dev-token" }
Invoke-RestMethod -Headers $headers http://127.0.0.1:8000/api/lpg/lpg01/latest
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/lpg/lpg01/history?minutes=60"
```

FastAPI interactive documentation is available at `http://127.0.0.1:8000/docs`.

## 8. Running the ESP32 Device

1. Open `firmware/LPG_Device/LPG_Device.ino` as an ESP32 Dev Module project.
2. In `config.h`, set the 2.4 GHz Wi-Fi credentials and the MQTT host computer's LAN IPv4 address.
3. Confirm the MQ-2 load resistor and voltage-divider values.
4. Power the MQ-2 from 5 V and connect its divided analog output to GPIO34.
5. Connect the DHT22 to GPIO4, relay to GPIO23, servo signal to GPIO13, and buzzer to GPIO27.
6. Give the servo a separate suitable 5–6 V supply with common ground.
7. Use `CALIBRATE_MODE` in clean air after the sensor burn-in, copy the suggested `MQ2_R0_OHM`, and return to normal mode.
8. Use `HARDWARE_TEST_MODE` to confirm relay polarity, servo direction, and buzzer operation before relying on automatic control.
9. Flash the firmware and monitor the serial output at 115200 baud.

Do not commit real Wi-Fi credentials. `MQTT_HOST` must be the backend computer's LAN address, not `127.0.0.1`.

## 9. Mobile Application

The Flutter LPG screen shows:

- the current compensated ppm gauge;
- semantic safety tier and prediction source;
- temperature and humidity;
- gas history as a line chart;
- exhaust fan and window controls; and
- an offline edge-operation warning.

The application first obtains a REST snapshot and then updates through `/ws/live`. Manual commands travel back through the API and MQTT to the physical device or simulator.

## 10. Testing

Run backend tests from the repository root:

```powershell
python -m pytest backend/tests -q
```

Run Flutter tests from `frontend`:

```powershell
flutter test
flutter analyze
```

Relevant coverage includes LPG feature arithmetic, schema validation, MQTT routing, API latest/history routes, command publication, Dart model deserialization, and the LPG command UI.

## 11. Safety and Current Limitations

- This is a research prototype, not a certified domestic gas alarm.
- MQ-2 values are not reliable until the individual sensor is burned in and calibrated.
- Temperature/humidity compensation is reserved in the feature set but still requires measured calibration.
- The development MQTT broker allows anonymous access and the API uses a development bearer token.
- The optional trained model is not required for operation; deterministic rules remain active when it is missing.
- Manual commands cannot be allowed to defeat the critical edge safety response.
- Production deployment requires authenticated MQTT, TLS/HTTPS, secure secret storage, persistent feature state, and formal hardware validation.

