# KitchenGuard Flutter client

Phase 4 is a single Flutter app for the LPG, pantry, pest, and child-safety modules exposed by the Phase 0 backend.

## Toolchain

Install the latest stable Flutter SDK. The Android runner is already generated and configured in `frontend/android`; fetch packages before the first build:

```powershell
cd frontend
flutter pub get
```

Android has been built and verified on a physical device. An iOS runner has not been generated or tested in this workspace.

## Run

Android emulator defaults to the host backend at `10.0.2.2:8000`:

```powershell
flutter run --dart-define=API_TOKEN=dev-token
```

For iOS Simulator or a physical device, provide the development machine's reachable address:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000 --dart-define=API_TOKEN=dev-token
```

Device IDs are centralized and can also be overridden at build time:

- `LPG_DEVICE_ID` (default `lpg01`)
- `PANTRY_BANANA_DEVICE_ID` (default `pantry-banana01`)
- `PANTRY_POTATO_DEVICE_ID` (default `pantry-potato01`)
- `PEST_DEVICE_ID` (default `pest-kitchen01`)
- `CHILD_DEVICE_ID` (default `child-cam01`)

## Test

```powershell
flutter test
```

## Confirmed backend behavior

The current pantry simulator publishes two devices, `pantry-banana01` and `pantry-potato01`; the app therefore shows two dashboard cards and sends the matching compartment query for each device.

Live frame types are `lpg`, `pantry`, `pest`, `child`, `alert`, `deterrence_trial`, `device_status`, and `cmd`. The client consumes the first six relevant data types through one reconnecting WebSocket.

The current pest history endpoint returns only `pest_events`; there is no REST endpoint for stored deterrence trials and no `trial_id` on a `PestEvent`. Pending trials can therefore be reviewed when their `deterrence_trial` frame arrives live, but cannot be rediscovered after restarting the app until the backend adds a read contract for trials.

The backend WebSocket hub applies FastAPI `jsonable_encoder` to complete frames before `send_json`, so outer Python `datetime` fields are JSON-safe for LPG, pantry, pest, and child live updates.

For the complete Windows preview, USB debugging, architecture, troubleshooting, design-system, and agent-handoff guide, see the repository-level [README](../README.md).
