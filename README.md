# KitchenGuard

KitchenGuard is the SLIIT project **J26-IT-428**: one Flutter mobile application backed by a FastAPI service, MQTT device messaging, MongoDB-compatible persistence, shared Pydantic contracts, four hardware simulators, and optional machine-learning artifacts.

This README is both the operator guide and the engineering handoff. It records the repository's current behavior, the work completed so far, the commands that have been verified on Windows, and the constraints a future developer or AI agent must preserve.

## Current Status

Implemented and working:

- FastAPI backend with REST and live WebSocket APIs.
- Canonical shared schemas used by both the backend and simulators.
- MQTT ingestion, routing, command publication, alert generation, and persistence.
- LPG, pantry, pest, and child-safety simulators.
- MongoDB production/dev storage plus an in-memory preview/test repository.
- Optional LPG and pantry model loading with safe rule fallbacks.
- One Flutter Android application with all four feature modules.
- Riverpod state management, Dio REST calls, reconnecting WebSocket updates, local danger notifications, and GoRouter navigation.
- A complete calm, professional mobile UI redesign with shared theme tokens and components.
- A Windows-friendly, one-command preview stack that embeds MQTT, the API, in-memory storage, and all simulators.
- Android USB-debugging workflow using `adb reverse`.
- Backend and Flutter tests.

Verified development environment:

- Windows with PowerShell.
- Flutter `3.47.6` and Dart `3.13.5` at `C:\Users\Sudu Mahaththaya\Documents\flutter`.
- Android SDK at `C:\Android`.
- JDK 17.
- Xiaomi `2201116SI`, ADB serial `a4a4b433427d`.
- Android package/application ID `com.example.kitchenguard`.
- Python 3.12 was used successfully; the project declares Python 3.11+ support.

## System Architecture

```text
LPG simulator -----------+
Pantry simulator --------+                         +--> REST API --> Flutter providers
Pest simulator ----------+--> MQTT broker --> FastAPI
Child simulator ---------+        1883          |  +--> WebSocket --> live Flutter updates
                                                |
                                                +--> MongoDB or in-memory repositories
                                                |
Flutter manual controls --> REST command API ---+--> MQTT cmd topic --> LPG simulator/device
```

The primary data path is:

1. A simulator or physical device publishes a versioned JSON message to MQTT.
2. `backend/app/mqtt/router.py` validates it with the shared schema package.
3. The backend computes features and model/fallback predictions where applicable.
4. The result is stored in MongoDB or the in-memory database.
5. The result is broadcast to `/ws/live` for immediate mobile updates.
6. The Flutter app combines initial REST snapshots with subsequent WebSocket frames.
7. High-severity alerts can trigger Android local notifications.

Manual LPG controls travel in the opposite direction:

1. Flutter posts `{action, value}` to the LPG command endpoint.
2. FastAPI creates and logs a canonical `ActuatorCommand`.
3. The backend publishes it to `kitchenguard/lpg/{device_id}/cmd`.
4. The LPG simulator/device applies the fan or window state.
5. The refreshed state returns through telemetry and REST/WebSocket updates.

## Repository Map

```text
backend/
  app/
    api/                   REST routes, auth stub, and WebSocket live hub
    core/                  environment configuration and logging
    db/                    MongoDB and in-memory database implementations
    mqtt/                  MQTT client and validated message router
    services/              features, inference, child fusion, and pest logic
  tests/                   backend API, feature, MQTT, and schema tests
  preview_stack.py         embedded local broker + API + all simulators
  requirements.txt         Python runtime/test dependencies

frontend/
  android/                 generated and configured Android host project
  lib/
    core/                  API client, config, router, theme, notifications, WS
    features/              home, LPG, pantry, pest, child, and alerts
    models/                Dart models for backend contracts
    shared/widgets/        shared calm surfaces, badges, charts, and states
    main.dart              Flutter entry point and live-alert listener
  test/                    model, status badge, and LPG command widget tests
  pubspec.yaml             Flutter/Dart dependencies

shared_schemas/
  kitchenguard_schemas/    canonical Pydantic contracts for every component

simulators/
  lpg_sim.py               LPG telemetry and command subscriber
  pantry_sim.py            banana and potato compartment telemetry
  pest_sim.py              pest events and deterrence trials
  child_sim.py             people, pose, hazard, and risk scenarios
  run_all.py               launches all simulators against an MQTT broker

firmware/                  ESP32 LPG device firmware (Arduino sketch + README)
docs/architecture.md       detailed topic, schema, storage, and API reference
ml/models/                 optional local .joblib artifacts
mosquitto/config/          anonymous local-development broker configuration
docker-compose.yml         Mosquitto, MongoDB, Mongo Express, and backend
```

## Four Feature Modules

### LPG Safety

The LPG module receives raw gas ppm, temperature, humidity, fan state, window position, edge tier, and offline-mode status. The backend computes seven Phase 0 features and produces a cloud tier.

The mobile screen provides:

- Current compensated ppm gauge.
- `Safe`, `Warning`, `Dangerous`, or `Critical` status.
- Raw ppm, temperature, and humidity readouts.
- Historical line chart.
- Exhaust fan switch.
- Window switch.
- Offline edge-operation warning.

### Pantry Monitoring

Two simulated devices are represented:

- `pantry-banana01`, compartment `banana`.
- `pantry-potato01`, compartment `potato`.

The mobile screen provides:

- Banana/potato segmented selection.
- Freshness percentage and stage.
- Remaining shelf-life countdown.
- MQ-3, MQ-135, temperature, and humidity readings.

### Pest Monitoring

Pest events include zone, trigger source, camera visibility, optional YOLO class, and confidence. Deterrence trials can arrive live and receive a human verdict.

The mobile screen provides:

- Zone filter.
- Detection history.
- Trigger source and confidence.
- Pending deterrence reviews.
- `Left` or `Remains` manual verdict submission.

### Child Safety

The child module transports normalized person boxes, hazard boxes, and pose points. Raw camera images are intentionally not accepted or stored.

The mobile screen provides:

- `Safe`, `Warning`, or `Danger` risk state.
- Human-readable reason for unsafe states.
- Rendered scene map with people, hazards, and pose skeletons.
- Child, adult, and hazard legend.

## Mobile UI Design System

The original functional UI was redesigned into a restrained light calmorphism system. The design is operational rather than decorative: important live data remains easy to scan and controls remain conventional.

Core visual decisions in `frontend/lib/core/theme.dart`:

- Background: cool off-white `#F1F5F3`.
- Main ink: deep green-black `#182420`.
- Primary accent: calm teal `#176B5B`.
- Semantic safe, warning, dangerous, and critical colors remain distinct.
- Surfaces use 8 px corners, light borders, and subtle dual shadows.
- Typography uses a consistent Material text scale with no viewport-based font scaling.
- Android touch controls retain at least 48 dp targets.
- Bottom navigation has five predictable destinations.
- Status is communicated with text and color, never color alone.
- Shared loading, empty, and error states are used across features.

Important shared components:

| File | Responsibility |
| --- | --- |
| `calm_surface.dart` | Reusable soft surface, section heading, and icon container. |
| `risk_badge.dart` | Semantic status chip and danger emphasis. |
| `gauge_speedometer.dart` | LPG range visualization and needle. |
| `freshness_bar.dart` | Pantry freshness visualization. |
| `shelf_life_countdown.dart` | Live remaining-life display. |
| `loading_error_view.dart` | Standard loading, empty, retry, and offline states. |

The redesigned application was inspected on the connected Xiaomi at its physical `1080x2400` resolution. Home, LPG, pantry, and child-safety rendering were checked for visible overflow and navigation problems.

## Prerequisites

### Required for the lightweight Windows preview

- Python 3.11 or newer.
- Flutter stable.
- Android SDK/platform tools.
- JDK 17.
- Android phone with Developer Options and USB debugging enabled.
- `Install via USB` enabled on Xiaomi/MIUI when Android blocks ADB installation.

Install Python dependencies from the repository root:

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system"
python -m pip install -r .\backend\requirements.txt
python -m pip install amqtt==0.12.1
```

`amqtt` is only needed by `backend/preview_stack.py`, which embeds a broker so Docker is not required for phone previews.

Fetch Flutter dependencies:

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system\frontend"
& "C:\Users\Sudu Mahaththaya\Documents\flutter\bin\flutter.bat" pub get
```

## Recommended Windows + USB Workflow

Use two PowerShell terminals.

### Terminal 1: Backend, broker, and simulators

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system"
python .\backend\preview_stack.py
```

Keep this terminal open. The command starts:

- An embedded anonymous MQTT broker on `127.0.0.1:1883`.
- FastAPI on `127.0.0.1:8000`.
- In-memory persistence via `USE_MEMORY_DB=true`.
- LPG, pantry, pest, and child simulators.
- MQTT ingestion inside the backend.

Use a faster simulation when needed:

```powershell
$env:PREVIEW_SPEED = "10"
python .\backend\preview_stack.py
```

The default speed is `1`. High speeds intentionally generate data and alerts much faster.

Verify the backend:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/healthz
```

Expected result:

```text
status
------
ok
```

### Terminal 2: Phone tunnel and Flutter debug session

Confirm that the phone is authorized:

```powershell
C:\Android\platform-tools\adb.exe devices -l
```

Expected device for the verified setup:

```text
a4a4b433427d  device  model:2201116SI
```

Create the host-to-phone tunnel:

```powershell
C:\Android\platform-tools\adb.exe reverse tcp:8000 tcp:8000
```

Run the application:

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system\frontend"

& "C:\Users\Sudu Mahaththaya\Documents\flutter\bin\flutter.bat" run `
  -d a4a4b433427d `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Flutter debug keys:

| Key | Action |
| --- | --- |
| `r` | Hot reload. |
| `R` | Full hot restart. |
| `h` | Show available commands. |
| `d` | Detach Flutter while leaving the app running. |
| `q` | Stop the debug session and app. |

### Reattach to a running debug application

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system\frontend"
& "C:\Users\Sudu Mahaththaya\Documents\flutter\bin\flutter.bat" attach -d a4a4b433427d
```

### Install an already-built APK without Flutter attach

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system"

C:\Android\platform-tools\adb.exe reverse tcp:8000 tcp:8000

C:\Android\platform-tools\adb.exe install -r `
  ".\frontend\build\app\outputs\flutter-apk\app-debug.apk"

C:\Android\platform-tools\adb.exe shell am start `
  -n com.example.kitchenguard/.MainActivity
```

### Build the debug APK manually

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system\frontend"

& "C:\Users\Sudu Mahaththaya\Documents\flutter\bin\flutter.bat" build apk `
  --debug `
  --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Output:

```text
frontend\build\app\outputs\flutter-apk\app-debug.apk
```

## Why `adb reverse` Is Required

Inside the phone, `127.0.0.1` normally means the phone itself. This command maps the phone's port `8000` back to the development computer's port `8000`:

```powershell
C:\Android\platform-tools\adb.exe reverse tcp:8000 tcp:8000
```

The mapping is temporary. It is commonly cleared when:

- The USB cable is unplugged.
- USB mode changes.
- ADB restarts.
- The phone reconnects with a new transport ID.
- Flutter reports `Lost connection to device` after a transient USB reset.

After any USB reconnection, run `adb reverse` again. Confirm it with:

```powershell
C:\Android\platform-tools\adb.exe reverse --list
```

Expected output includes:

```text
UsbFfs tcp:8000 tcp:8000
```

If Flutter says `Lost connection to device` but the app remains open, the app probably did not crash. Check:

```powershell
C:\Android\platform-tools\adb.exe devices -l
C:\Android\platform-tools\adb.exe shell pidof com.example.kitchenguard
```

Restore the reverse rule and either keep using the app or run `flutter attach`.

## Docker Workflow

The full infrastructure workflow uses Mosquitto, MongoDB, Mongo Express, and FastAPI.

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system"
Copy-Item .env.example .env
docker compose up --build
```

Services:

| Service | Address |
| --- | --- |
| FastAPI | `http://localhost:8000` |
| MQTT/Mosquitto | `localhost:1883` |
| MongoDB | `localhost:27017` |
| Mongo Express | `http://localhost:8081` |

Run all simulators against Mosquitto in another terminal:

```powershell
python .\simulators\run_all.py --host 127.0.0.1 --port 1883 --speed 1
```

For an accelerated pantry demonstration:

```powershell
python .\simulators\run_all.py --host 127.0.0.1 --port 1883 --speed 60
```

The development MQTT broker permits anonymous access. This is only appropriate for local demonstrations.

## Configuration

### Backend environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `DEV_API_TOKEN` | `dev-token` | Bearer token for all REST routes except `/healthz`. |
| `MONGO_URL` | `mongodb://mongo:27017` | MongoDB connection string. |
| `MONGO_DB` | `kitchenguard` | Database name. |
| `MQTT_HOST` | `mosquitto` | MQTT broker host. |
| `MQTT_PORT` | `1883` | MQTT broker port. |
| `MQTT_CLIENT_ID` | `kitchenguard-backend` | Backend broker identity. |
| `ML_MODELS_DIR` | `/app/ml/models` | Optional artifact directory. |
| `START_MQTT` | `true` | Start backend MQTT consumer. |
| `USE_MEMORY_DB` | `false` | Use ephemeral in-memory storage instead of MongoDB. |
| `PREVIEW_SPEED` | `1` | Simulator speed used by `preview_stack.py`. |

### Flutter build-time variables

These are compile-time `--dart-define` values.

| Variable | Default | Meaning |
| --- | --- | --- |
| `API_BASE_URL` | `http://10.0.2.2:8000` | REST base URL; also used to derive `/ws/live`. |
| `API_TOKEN` | `dev-token` | Development bearer token. |
| `LPG_DEVICE_ID` | `lpg01` | LPG device shown by the app. |
| `PANTRY_BANANA_DEVICE_ID` | `pantry-banana01` | Banana pantry device. |
| `PANTRY_POTATO_DEVICE_ID` | `pantry-potato01` | Potato pantry device. |
| `PEST_DEVICE_ID` | `pest-kitchen01` | Pest device. |
| `CHILD_DEVICE_ID` | `child-cam01` | Child camera/edge node. |

The Android manifest permits cleartext HTTP for local development. Production deployment should use HTTPS/WSS and remove the cleartext allowance.

## Network Contract

MQTT topics use:

```text
kitchenguard/{component}/{device_id}/{channel}
```

Examples:

```text
kitchenguard/lpg/lpg01/telemetry
kitchenguard/lpg/lpg01/cmd
kitchenguard/pantry/pantry-banana01/telemetry
kitchenguard/pest/pest-kitchen01/event
kitchenguard/child/child-cam01/event
```

REST endpoints:

| Method and path | Purpose |
| --- | --- |
| `GET /healthz` | Unauthenticated service health. |
| `GET /api/devices` | Device status list. |
| `GET /api/lpg/{id}/latest` | Latest LPG document. |
| `GET /api/lpg/{id}/history?minutes=60` | LPG history. |
| `POST /api/lpg/{id}/cmd` | Fan/window command. |
| `GET /api/pantry/{id}/latest?compartment=banana` | Latest pantry document. |
| `GET /api/pest/{id}/events?limit=50` | Pest event history. |
| `POST /api/pest/{id}/trials/{trial_id}/review` | Manual deterrence review. |
| `GET /api/child/{id}/latest` | Latest child-safety result. |
| `GET /api/alerts?acknowledged=false` | Filtered alerts. |
| `POST /api/alerts/{alert_id}/ack` | Acknowledge an alert. |
| `WS /ws/live` | Live frames for all components. |

All `/api` routes require:

```text
Authorization: Bearer dev-token
```

WebSocket frames use:

```json
{
  "type": "lpg",
  "data": {}
}
```

Live types currently include `lpg`, `pantry`, `pest`, `child`, `alert`, `deterrence_trial`, `device_status`, and `cmd`.

The WebSocket hub now calls FastAPI's `jsonable_encoder` before `send_json`. This was added because outer document timestamps were Python `datetime` objects and previously failed standard JSON serialization while a client was connected.

For the complete schema field reference, storage collection map, and inference rules, see [docs/architecture.md](docs/architecture.md).

## Smoke Tests

With the backend and simulators running:

```powershell
$headers = @{ Authorization = "Bearer dev-token" }

Invoke-RestMethod -Headers $headers http://127.0.0.1:8000/api/devices
Invoke-RestMethod -Headers $headers http://127.0.0.1:8000/api/lpg/lpg01/latest

Invoke-RestMethod `
  -Method Post `
  -Headers $headers `
  -ContentType "application/json" `
  -Body '{"action":"fan","value":1}' `
  http://127.0.0.1:8000/api/lpg/lpg01/cmd
```

FastAPI interactive docs are available at `http://127.0.0.1:8000/docs`.

## Tests and Quality Checks

### Backend

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system\backend"
python -m pytest -q
```

Last verified result: **6 passed**. The suite uses in-memory repositories and direct MQTT-router calls, so Docker, MongoDB, and a real broker are not required.

### Flutter

```powershell
cd "C:\Users\Sudu Mahaththaya\Desktop\Work\Hasi\system\frontend"

& "C:\Users\Sudu Mahaththaya\Documents\flutter\bin\flutter.bat" test
& "C:\Users\Sudu Mahaththaya\Documents\flutter\bin\flutter.bat" analyze
```

Last verified result: **20 tests passed** and **no analysis issues**.

Coverage includes:

- Dart model deserialization for backend contracts.
- Shared status-to-color mapping.
- LPG fan command submission and refreshed UI state.

## Optional ML Artifacts and Fallbacks

Copy trained artifacts into `ml/models/`:

```text
lpg_rf_backend.joblib
pantry_models_backend.joblib
```

When they are absent, startup warnings are expected and the backend continues safely.

Fallback behavior:

- LPG: `Safe < 150`, `Warning < 300`, `Dangerous < 700`, and `Critical >= 700` ppm. The hard 700 ppm override always wins.
- Pantry: Phase 0 placeholder returns `100` freshness, `999` hours remaining, and `Fresh`.
- Child safety: overlap between a person and hazard produces `Warning`; otherwise `Safe`.
- Pest monitoring currently has no model layer.

The warning `ML model ... is missing; using documented rule fallback` is informational, not fatal.

## Troubleshooting

### Port 8000 is already in use

Error:

```text
[WinError 10048] only one usage of each socket address is normally permitted
```

Another backend is already running. Check its health before starting a duplicate:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/healthz
```

Find the listener:

```powershell
Get-NetTCPConnection -LocalPort 8000 -State Listen |
  Select-Object LocalAddress, LocalPort, OwningProcess
```

Stop that specific process only when a restart is required:

```powershell
$backendPid = (Get-NetTCPConnection -LocalPort 8000 -State Listen).OwningProcess
Stop-Process -Id $backendPid
```

Then rerun `python .\backend\preview_stack.py`.

### Preview broker warnings

These `amqtt` messages are non-fatal in the local preview:

```text
Configuration parameter 'password-file' not found
Loading plugins from EntryPoints is deprecated
```

### ADB shows `unauthorized`

1. Unlock the phone.
2. Accept the USB-debugging fingerprint prompt.
3. Optionally select `Always allow from this computer`.
4. Run `adb devices -l` again.

### APK installation is blocked

On Xiaomi/MIUI, enable both USB debugging and `Install via USB` in Developer Options. The observed error was `INSTALL_FAILED_USER_RESTRICTED`.

### Flutter reports `Lost connection to device`

This can be a transient USB reset. The installed app may still be running. Verify the device and process, rerun `adb reverse`, then use `flutter attach` if hot reload is needed.

### App shows reconnecting or no live data

Check all three layers:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/healthz
C:\Android\platform-tools\adb.exe devices -l
C:\Android\platform-tools\adb.exe reverse --list
```

If the reverse list is empty:

```powershell
C:\Android\platform-tools\adb.exe reverse tcp:8000 tcp:8000
```

### Alert badge shows `99+`

Accelerated simulators can quickly create many alerts. Acknowledging alerts clears unread state. Restarting an in-memory preview stack also clears its ephemeral database; restart the Flutter process to reload the fresh alert list.

## Known Phase 0 Limitations

- Authentication is a hardcoded development bearer token, not user login/JWT.
- The embedded preview broker and Docker Mosquitto configuration are anonymous and unencrypted.
- In-memory preview data disappears when `preview_stack.py` stops.
- LPG and pantry rolling feature buffers reset when the backend restarts.
- The pantry fallback is deliberately a placeholder until trained models are supplied.
- Pest history REST returns pest events only. There is no endpoint to reload pending deterrence trials after the app restarts; pending trials are currently discovered through live WebSocket frames.
- Child safety intentionally stores geometry and keypoints, never raw images.
- Android cleartext traffic is enabled for local USB development.
- Only the Android runner has been generated and tested in this workspace. iOS has not been configured or verified.
- The application ID remains `com.example.kitchenguard`; replace it before a store/release build.
- Notification permission and delivery behavior can vary by Android/MIUI power-management settings.

## Important Guidance for Future Agents

Before changing this project:

1. Read this README and `docs/architecture.md`.
2. Inspect `git status --short`; do not discard user changes.
3. Preserve `shared_schemas` as the canonical Python contract source.
4. Keep Flutter model keys aligned with serialized backend documents.
5. Preserve the REST-initial-load plus WebSocket-live-update model.
6. Use semantic status colors from `frontend/lib/core/theme.dart`, not per-screen hardcoded replacements.
7. Reuse `CalmSurface`, `SectionHeading`, `SoftIcon`, `RiskBadge`, and standard loading/error states.
8. Keep cards at 8 px radius and maintain the 4/8 dp spacing rhythm.
9. Preserve minimum Android touch targets and accessibility semantics.
10. Do not reintroduce raw child-camera image transport.
11. Keep `jsonable_encoder` in `backend/app/api/ws.py`; removing it breaks datetime WebSocket frames.
12. Run backend tests, Flutter tests, and static analysis after behavioral changes.
13. For visual changes, build an APK and inspect it on a real phone at multiple screens and scroll positions.
14. Remember that `adb reverse` is transport-scoped and must be recreated after USB reconnects.

## Work Completed During the Latest Implementation

- Located and used the existing Flutter SDK despite it not being on `PATH`.
- Generated and configured the Android host project under `frontend/android/`.
- Added Android Internet permission, local cleartext support, Java desugaring, and JDK-compatible build configuration.
- Built and installed the debug APK on the Xiaomi device.
- Added `backend/preview_stack.py` to avoid Docker dependencies during local phone previews.
- Configured the preview stack with a Windows `SelectorEventLoop`.
- Added an embedded `amqtt` broker and all four simulators to that preview process.
- Fixed WebSocket serialization of Python `datetime` values with `jsonable_encoder`.
- Set up and verified USB `adb reverse` forwarding.
- Redesigned the complete Flutter UI into a calm professional system.
- Added `CalmSurface`, `SectionHeading`, and `SoftIcon` shared components.
- Redesigned Home, LPG, Pantry, Pest, Child Safety, Alerts, and the deterrence review sheet.
- Improved hierarchy, charts, touch targets, semantic labels, loading states, and navigation.
- Corrected the LPG widget test so its switch is visible before the test taps it.
- Verified 20 Flutter tests, clean Dart analysis, six backend tests, APK compilation, installation, live data, and real-device rendering.

## Related Documentation

- [Detailed architecture and schemas](docs/architecture.md)
- [Flutter-specific notes](frontend/README.md)
- [Model artifact notes](ml/models/README.md)
