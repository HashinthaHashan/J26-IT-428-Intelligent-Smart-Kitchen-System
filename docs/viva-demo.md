# Viva hardware demo

## One-time preparation

1. Connect the laptop and all ESP32 boards to the same 2.4 GHz hotspot.
2. Confirm the laptop Wi-Fi IPv4 address is the `MQTT_HOST` in each board's `config.h`.
3. Upload the latest LPG, pantry, and pest sketches. The latest firmware uses an 8-second MQTT keepalive so a removed board becomes offline in about 12 seconds.
4. The pantry sketch has `VIVA_DEMO_MODE 1`: it warms up for 10 seconds and publishes every 5 seconds. Set it to `0` after the viva to restore the production 180-second warm-up and 60-second sample interval.

## Start the demo

From the repository root:

```powershell
$env:PREVIEW_SIMULATORS='child'
.\.venv312\Scripts\python.exe backend\preview_stack.py
```

For the Samsung phone build (configured for device port 8001):

```powershell
adb reverse tcp:8001 tcp:8000
```

Keep this terminal and the phone connected during the demonstration.

## Presentation order

1. Begin with LPG, pantry, and pest powered off. Their dashboard cards and screens must say **Offline**; old readings must not be shown as live.
2. Power LPG. Within a few seconds, its screen shows **Device online** and live readings. Pantry and pest remain offline.
3. Remove LPG power. It should switch to offline in about 12 seconds. Power pantry; it shows online immediately and starts fresh readings after its 10-second demo warm-up. LPG and pest remain offline.
4. Remove pantry power. After it switches offline, power pest. It shows online immediately. Allow 45 seconds for the PIR sensor's physical warm-up before demonstrating a trigger.
5. Remove pest power and confirm it switches offline rather than keeping the last event on screen.

The mobile app also polls `/api/devices` every five seconds, so a status missed during a WebSocket reconnect is corrected automatically.

## Quick checks

- Backend: open `http://127.0.0.1:8000/healthz` and expect `{"status":"ok"}`.
- Physical MQTT clients: `netstat -ano | Select-String ':1883'`.
- Device status API: call `/api/devices` with bearer token `dev-token`.
- If a board stays offline, check its Serial Monitor for Wi-Fi IP, MQTT connection, and the configured broker address.
