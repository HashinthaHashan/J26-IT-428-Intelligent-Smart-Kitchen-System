"""Validates the firmware's telemetry JSON shape against the backend schema.

Run from the repo root:
    python firmware/tools/check_contract.py

The payload below is a literal copy of what mqtt_client.cpp builds (same keys,
same order, same number formatting). If the backend schema changes, this fails
and tells you which field no longer matches.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "shared_schemas"))

from kitchenguard_schemas import ActuatorCommand, LpgTelemetry, PantryTelemetry  # noqa: E402

FIRMWARE_KEYS = [
    "schema_version", "device_id", "ts", "seq", "ppm_raw", "temp_c", "rh_pct",
    "fan_on", "window_frac", "edge_tier", "edge_offline_mode",
]

samples = [
    '{"schema_version":1,"device_id":"lpg01","ts":"2026-10-07T12:00:00Z","seq":0,'
    '"ppm_raw":4.0,"temp_c":30.1,"rh_pct":67.0,"fan_on":false,"window_frac":0.0,'
    '"edge_tier":"Safe","edge_offline_mode":false}',
    '{"schema_version":1,"device_id":"lpg01","ts":"2026-10-07T12:00:05Z","seq":5,'
    '"ppm_raw":812.5,"temp_c":30.4,"rh_pct":66.5,"fan_on":true,"window_frac":0.9,'
    '"edge_tier":"Critical","edge_offline_mode":true}',
]

for raw in samples:
    data = json.loads(raw)
    assert list(data) == FIRMWARE_KEYS, f"key set/order differs: {list(data)}"
    msg = LpgTelemetry.model_validate_json(raw)  # extra='forbid' => exact fields
    print("telemetry OK:", msg.edge_tier, msg.ppm_raw)

# Command as the backend publishes it (api/lpg.py + mqtt/router.py override).
for cmd in (
    ActuatorCommand(device_id="lpg01", component="lpg", action="fan", value=1,
                    source="manual", issued_by="dev", ts="2026-10-07T12:00:00Z"),
    ActuatorCommand(device_id="lpg01", component="lpg", action="window", value=0.5,
                    source="override", ts="2026-10-07T12:00:00Z"),
):
    data = json.loads(cmd.model_dump_json())
    for key in ("device_id", "component", "action", "value", "source"):
        assert key in data, key
    print("command shape OK:", data["action"], data["value"], data["source"])
# --- Smart Pantry sensor board (Pantry_Sensor_Device/mqtt_client.cpp) -------------
PANTRY_KEYS = [
    "schema_version", "device_id", "compartment", "ts", "mq3_ppm", "mq135_ppm",
    "temp_c", "rh_pct", "mass_kg", "item_count", "hue_mean", "brown_pct", "green_pct",
]
pantry_samples = [
    '{"schema_version":1,"device_id":"pantry01","compartment":"banana","ts":"2026-10-07T12:00:00Z",'
    '"mq3_ppm":0.44,"mq135_ppm":4.3,"temp_c":26.7,"rh_pct":43.2,"mass_kg":null,"item_count":null,'
    '"hue_mean":null,"brown_pct":null,"green_pct":null}',
    '{"schema_version":1,"device_id":"pantry01","compartment":"potato","ts":"2026-10-07T12:00:00Z",'
    '"mq3_ppm":0.44,"mq135_ppm":4.3,"temp_c":26.7,"rh_pct":43.2,"mass_kg":null,"item_count":null,'
    '"hue_mean":null,"brown_pct":null,"green_pct":null}',
]
for raw in pantry_samples:
    data = json.loads(raw)
    assert list(data) == PANTRY_KEYS, f"pantry key set/order differs: {list(data)}"
    msg = PantryTelemetry.model_validate_json(raw)
    print("pantry telemetry OK:", msg.compartment, msg.mq3_ppm, msg.mq135_ppm)
print("ALL OK")
