# KitchenGuard — Intelligent Smart Kitchen System

**SLIIT Final-Year Research Project | Project ID: J26-IT-428**

KitchenGuard is an integrated smart-kitchen research prototype combining **Internet of Things (IoT)** sensing, **AI/ML-assisted analysis**, automated safety responses, and a unified **Flutter Android application**. The system comprises four independently developed research components connected through a shared MQTT messaging layer, a Python FastAPI backend, common Pydantic schemas, and MongoDB-compatible storage.

> **Research prototype:** KitchenGuard is intended for academic demonstration and evaluation. It is not a certified gas alarm, child-protection device, food-safety instrument, or commercial pest-control system.

## Contents

- [Research Components](#research-components)
- [System Architecture](#system-architecture)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Android Application](#android-application)
- [MQTT and API Interfaces](#mqtt-and-api-interfaces)
- [AI/ML Models and Fallbacks](#aiml-models-and-fallbacks)
- [Testing](#testing)
- [Security, Privacy and Limitations](#security-privacy-and-limitations)
- [Additional Documentation](#additional-documentation)

## Research Components

| Component | Primary purpose | Main hardware / input | Application features |
| --- | --- | --- | --- |
| **LPG Leak Detection and Response** | Monitor LPG and respond to dangerous gas levels, including when connectivity is lost | ESP32, MQ-2, DHT22, exhaust-fan relay, window servo, buzzer | Gas gauge, risk tier, history, fan/window controls, offline warning |
| **Smart Pantry Freshness Monitoring** | Estimate banana/potato freshness and remaining shelf life | ESP32, MQ-3, MQ-135, DHT22; optional ESP32-CAM | Freshness percentage, stage, shelf-life countdown, gas/climate readings |
| **Pest Detection and Smart Deterrence** | Detect possible pests, request camera classification and evaluate non-chemical deterrents | ESP32 with PIR, IR, vibration and light sensing; ESP32-CAM; motor/LED/optional buzzer | Event history, zone filtering, classifications, deterrence reviews |
| **Child Safety Monitoring** | Assess child-related kitchen hazards from person/hazard geometry and pose data | Child simulator or camera/edge node providing normalized geometry | Safe/Warning/Danger UI, reasons for unsafe conditions, scene visualization |

### 1. LPG Leak Detection and Response

The LPG component samples gas and environmental measurements on an ESP32, computes short- and long-window features, and controls a fan, window servo, and buzzer. **Edge-side safety actions continue independently of Wi-Fi, MQTT, or backend availability.** The backend supports an optional Random Forest model and deterministic safety rules.

The documented fallback tiers are:

| Gas concentration | Safety tier |
| --- | --- |
| Below 150 ppm | `Safe` |
| 150 to below 300 ppm | `Warning` |
| 300 to below 700 ppm | `Dangerous` |
| 700 ppm or above | `Critical` — immediate hard override |

The backend's seven documented features are `ppm_comp`, `d_ppm_5s`, `slope_30s`, `ma10`, `ma30`, `d_rh_10s`, and `tt700_s`. Environmental compensation still requires calibration; currently `ppm_comp` equals raw ppm. Manual actuator commands must not override critical safety actions.

**Component documentation:** [IT23207554_README.md](IT23207554_README.md)

### 2. Smart Pantry Freshness Monitoring

The Pantry component uses MQ-3, MQ-135 and DHT22 measurements to monitor banana and potato compartments. It computes gas/climate time-series features and estimates a freshness score, stage, and remaining shelf life. The physical sensor firmware publishes both compartments under `pantry01`, because they share an airspace; the preview simulator uses separate logical IDs.

The documented freshness stages are:

| Freshness score | Stage |
| --- | --- |
| 75–100 | `Fresh` |
| 40–74.99 | `Ripe` |
| 15–39.99 | `Deteriorating` |
| Below 15 | `Spoiled` |

The component README describes a transparent rule fallback using MQ-3 and MQ-135 literature anchors and the formula `remaining hours = 168 × freshness score / 100`. This is **not** a trained research model. Optional ESP32-CAM firmware publishes banana/potato colour features, but the separate camera-channel data is **not yet merged** into the current backend prediction pipeline.

**Component documentation:** [IT23208094_README.md](IT23208094_README.md)

### 3. Pest Detection and Smart Deterrence

The Pest component uses a sensor/deterrent ESP32 and a separate ESP32-CAM. Confirmed sensor triggers create events and initiate deterrence trials **without waiting for camera classification**. A camera capture can then be requested, uploaded to the backend over authenticated development HTTP, and classified with an optional YOLO-compatible ONNX model.

Supported normalized classification labels are `rat`, `cockroach`, and `non_pest`. The documented warning rule applies to rat/cockroach detections at confidence **0.60 or higher**. If inference is unavailable, the event/trial workflow continues, but the species may remain unknown.

The four experimental deterrence conditions are `control`, `vibration_only`, `led_only`, and `vibration_led`. Users can submit `left` or `remains` manual trial verdicts through the Flutter application.

**Component documentation:** [IT23203594_README.md](IT23203594_README.md)

### 4. Child Safety Monitoring

The Child Safety component receives **normalized person bounding boxes, hazard bounding boxes, and pose keypoints**, processes them through backend child-fusion logic, and displays a human-readable risk assessment and scene visualization.

The documented Phase 0 fallback returns `Warning` when a person overlaps a hazard and `Safe` otherwise. The Flutter interface also supports displaying `Danger`, but the supplied documentation does **not** specify a separate `Danger` decision threshold. No additional rule is assumed here.

**Privacy design:** Raw child-camera images are intentionally not accepted or stored by this component; the backend processes geometry and pose information.

**Component documentation:** [ChildREADME_Refined.md](ChildREADME_Refined.md)

## System Architecture

```text
LPG ESP32 / Simulator -------------------+
Pantry ESP32 / Camera / Simulator -------+       +--> MongoDB / in-memory storage
Pest ESP32 / ESP32-CAM / Simulator ------+       |
Child edge geometry / Simulator --------+--> MQTT broker --> FastAPI backend
                                                   |             |
                                                   |             +--> REST API
                                                   |             +--> WebSocket /ws/live
                                                   |                       |
                                                   |                       v
                                                   |               Flutter Android app
                                                   |
Flutter controls --> REST commands --> FastAPI ----+--> MQTT device commands

Pest ESP32-CAM -------- HTTP photo upload --------> FastAPI pest pipeline
```

**Shared processing flow:** Devices or simulators publish versioned messages; `backend/app/mqtt/router.py` validates messages against `shared_schemas`; backend services process events, predictions, and alerts; repositories persist results; the Flutter app loads REST snapshots and receives subsequent WebSocket updates. The LPG and Pest components also support command/control paths.

## Technology Stack

| Layer | Technologies |
| --- | --- |
| Embedded and sensing | ESP32 Dev Module, ESP32-CAM, Arduino/C++, MQ-series sensors, DHT22, PIR/IR/vibration/light inputs |
| Actuation | Exhaust fan relay, servo, buzzer, vibration motor, LED |
| Messaging | MQTT, Mosquitto; embedded `amqtt` broker for local preview |
| Backend | Python 3.11+, FastAPI, Pydantic |
| Storage | MongoDB; in-memory preview/test repositories |
| AI/ML | Optional scikit-learn/joblib models for LPG and Pantry; optional YOLO ONNX/ONNX Runtime for Pest; documented Child Safety fusion rules |
| Mobile | Flutter, Dart, Riverpod, Dio, GoRouter, WebSocket, local Android notifications |
| Development/testing | PowerShell, Docker Compose, Pytest, Flutter test/analyze, Android Debug Bridge (ADB) |

## Repository Structure

```text
.
├── backend/
│   ├── app/
│   │   ├── api/                 # REST endpoints and WebSocket hub
│   │   ├── core/                # Configuration and logging
│   │   ├── db/                  # MongoDB and in-memory repositories
│   │   ├── mqtt/                # MQTT client and message routing
│   │   └── services/            # Features, inference, child fusion, pest pipeline
│   ├── tests/
│   ├── preview_stack.py         # Embedded broker, API, storage and simulators
│   └── requirements.txt
├── frontend/
│   ├── android/
│   ├── lib/
│   │   ├── core/                # REST, WebSocket, navigation, theme, notifications
│   │   ├── features/            # Home, LPG, Pantry, Pest, Child, Alerts
│   │   ├── models/
│   │   └── shared/widgets/
│   ├── test/
│   └── pubspec.yaml
├── firmware/                    # ESP32 component firmware
├── shared_schemas/              # Canonical Pydantic contracts
├── simulators/                  # lpg_sim, pantry_sim, pest_sim, child_sim
├── ml/models/                   # Optional model artifacts
├── mosquitto/config/
├── docs/
├── docker-compose.yml
├── .env.example
└── README.md
```

Refer to the individual component READMEs for the precise firmware folders, sensor pins, message schemas, and implementation files.

## Getting Started

### Prerequisites

- Python **3.11+** (Python 3.12 was used in the documented development environment).
- Flutter SDK and Dart.
- Android SDK/platform tools and **JDK 17** for Android builds.
- Windows PowerShell for the commands below.
- An Android device with USB debugging, or an appropriately configured emulator.
- Docker Desktop only for the full MongoDB/Mosquitto infrastructure workflow; **Docker is not required for the local preview**.

### Option A — Local preview without physical hardware

From the repository root, install the Python dependencies:

```powershell
python -m pip install -r .\backend\requirements.txt
python -m pip install amqtt==0.12.1
```

Start the development preview stack:

```powershell
python .\backend\preview_stack.py
```

This starts the local MQTT broker (`127.0.0.1:1883`), FastAPI (`127.0.0.1:8000`), ephemeral in-memory storage, and all four component simulators. Keep the terminal running.

To accelerate simulation for demonstrations:

```powershell
$env:PREVIEW_SPEED = "10"
python .\backend\preview_stack.py
```

Check the backend:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/healthz
```

Open interactive API documentation at `http://127.0.0.1:8000/docs`.

### Option B — Docker Compose infrastructure

From the repository root:

```powershell
Copy-Item .env.example .env
docker compose up --build
```

The documented Docker configuration includes FastAPI (`localhost:8000`), MQTT/Mosquitto (`localhost:1883`), MongoDB (`localhost:27017`), and Mongo Express (`http://localhost:8081`). Run the simulators in another terminal when required:

```powershell
python .\simulators\run_all.py --host 127.0.0.1 --port 1883 --speed 1
```

The included broker's anonymous configuration is for trusted local development only.

### Physical ESP32 devices

Follow the individual component READMEs for firmware upload, pin wiring, sensor burn-in and calibration, hardware self-tests, network setup, and camera configuration. For physical devices, configure the MQTT/API host to the **computer's LAN IPv4 address**, not the ESP32's own `127.0.0.1`. Hardware and actuators require appropriate power supplies and electrical protection.

## Android Application

The single Flutter application presents a home dashboard, LPG, Pantry, Pest, Child Safety, and alerts interfaces. It uses REST for initial data and `/ws/live` for real-time updates, with shared semantic risk colors, loading/error states, and Android local alerts.

Install dependencies:

```powershell
cd frontend
flutter pub get
```

For a USB-connected phone, establish reverse port forwarding from a separate terminal:

```powershell
adb devices
adb reverse tcp:8000 tcp:8000
```

Then, from `frontend`:

```powershell
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Re-run `adb reverse tcp:8000 tcp:8000` after USB reconnection. For an Android emulator, the documented default API host is `http://10.0.2.2:8000`. The Android application ID in the original development documentation is `com.example.kitchenguard` and should be changed before a production release.

## MQTT and API Interfaces

MQTT topics generally follow:

```text
kitchenguard/{component}/{device_id}/{channel}
```

Examples:

```text
kitchenguard/lpg/lpg01/telemetry
kitchenguard/lpg/lpg01/cmd
kitchenguard/pantry/pantry01/telemetry
kitchenguard/pantry/pantry01/camera
kitchenguard/pest/pest-kitchen01/event
kitchenguard/child/child-cam01/event
```

The physical Pantry firmware uses `pantry01`, while preview simulators use `pantry-banana01` and `pantry-potato01`.

### Key REST endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/healthz` | Service health (no bearer token) |
| `GET` | `/api/devices` | Device statuses |
| `GET` | `/api/lpg/{device_id}/latest` | Latest LPG result |
| `GET` | `/api/lpg/{device_id}/history?minutes=60` | LPG history |
| `POST` | `/api/lpg/{device_id}/cmd` | Fan/window command |
| `GET` | `/api/pantry/{device_id}/latest?compartment=banana` | Latest pantry result |
| `GET` | `/api/pantry/{device_id}/history?compartment=banana&minutes=1440` | Pantry history (component documentation) |
| `GET` | `/api/pest/{device_id}/events?limit=50` | Pest events |
| `GET` | `/api/pest/{device_id}/trials?limit=50` | Pest deterrence trials (component documentation) |
| `POST` | `/api/pest/{device_id}/trials/{trial_id}/review` | Manual pest trial verdict |
| `POST` | `/api/pest/{device_id}/cmd` | Manual pest trial command (component documentation) |
| `POST` | `/api/pest/{device_id}/photo` | Pest camera image upload (component documentation) |
| `GET` | `/api/child/{device_id}/latest` | Latest Child Safety result |
| `GET` | `/api/alerts?acknowledged=false` | Filtered alerts |
| `POST` | `/api/alerts/{alert_id}/ack` | Acknowledge alert |
| `WS` | `/ws/live` | Live component and alert frames |

Development REST routes under `/api` use `Authorization: Bearer dev-token` by default. The Pest photo endpoint also requires its documented request/image-format headers. The shared WebSocket hub uses FastAPI's `jsonable_encoder` for timestamp-safe JSON frames.

### Example smoke checks

```powershell
$headers = @{ Authorization = "Bearer dev-token" }
Invoke-RestMethod -Headers $headers http://127.0.0.1:8000/api/devices
Invoke-RestMethod -Headers $headers http://127.0.0.1:8000/api/lpg/lpg01/latest
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pantry/pantry-banana01/latest?compartment=banana"
Invoke-RestMethod -Headers $headers "http://127.0.0.1:8000/api/pest/pest-kitchen01/events?limit=50"
Invoke-RestMethod -Headers $headers http://127.0.0.1:8000/api/child/child-cam01/latest
```

## AI/ML Models and Fallbacks

| Component | Optional model / processing | Behavior without trained model |
| --- | --- | --- |
| LPG | `ml/models/lpg_rf_backend.joblib` (Random Forest) | Deterministic four-tier rules, with immediate critical override at 700 ppm |
| Pantry | `ml/models/pantry_models_backend.joblib` (compartment-specific models) | Component README documents a gas-anchor freshness rule; see note below |
| Pest | `ml/models/pest_yolo.onnx` (YOLO-compatible ONNX) | Event/capture/trial workflows continue, but species classification may be unavailable |
| Child Safety | Geometry-based child fusion | Documented person–hazard overlap fallback: `Warning` or `Safe` |

**Documentation discrepancy to verify against the current code:** The original overall README describes an older Pantry Phase 0 fallback of `100` freshness, `999` hours and `Fresh`, while the newer Pantry component README describes the gas-anchor scoring rule. This overview follows the **newer component README** for the intended Pantry behavior; confirm the checked-out `backend/app/services/pantry_rules.py` and inference path before presenting the rule as runtime-verified. Similarly, the original overall README says Pest has no model layer, while the newer Pest component README documents optional ONNX inference; the latter is reflected here.

## Testing

From the repository root:

```powershell
python -m pytest backend/tests -q
```

From `frontend`:

```powershell
flutter test
flutter analyze
```

The **original overall README** recorded **6 backend tests passed**, **20 Flutter tests passed**, and **no Flutter analysis issues** at the time of that verification. The newer component READMEs document additional component-specific tests; these historical totals should **not** be interpreted as fresh test results for the current repository. Re-run the commands above to obtain current counts.

Relevant testing areas include LPG feature calculations and commands; Pantry stage rules and history; Pest image decoding, model behavior, event correlation and deterrence trials; shared schema/API routing; and Flutter screen/model behavior.

## Security, Privacy and Limitations

- The project is an academic prototype, not a production-certified safety system.
- MQ gas sensors need individual burn-in, calibration, and experimental validation; cross-sensitivity affects ppm estimates.
- LPG environmental compensation and model performance require measured validation. Critical safety must remain enforced at the edge.
- Pantry camera features are not yet merged into the documented backend prediction pipeline; the rule fallback is not a trained model.
- Pest classification requires a compatible trained ONNX model and suitable images. Lighting, occlusion, and camera placement can affect results.
- Child Safety deliberately processes normalized geometry/pose data rather than raw camera images. The supplied documentation does not define a distinct `Danger` fallback threshold.
- The preview broker is anonymous and unencrypted; the API uses a development bearer token. Production needs authenticated MQTT, HTTPS/WSS, secret management, and access controls.
- In-memory preview data and some rolling feature buffers are lost on restart.
- Pest camera images are handled separately from Child Safety geometry; the Pest component README documents bounded local image retention and calls for explicit privacy/retention controls.
- The original development documentation verifies an Android build, not an iOS release.

## Additional Documentation

- [LPG component README](IT23207554_README.md)
- [Pantry component README](IT23208094_README.md)
- [Pest component README](IT23203594_README.md)
- [Child Safety component README](ChildREADME_Refined.md)
- [System architecture and contracts](docs/architecture.md)
- [Flutter development notes](frontend/README.md)
- [Model artifact notes](ml/models/README.md)
- [Viva demonstration checklist](docs/viva-demo.md)

> **Repository link note:** The four component README links above assume those files are committed at the repository root with the exact filenames shown. If they are stored in another directory or under different names, update the relative links accordingly.

---

**KitchenGuard · SLIIT · J26-IT-428**
