from __future__ import annotations

from datetime import datetime, timezone

from kitchenguard_schemas import ChildEvent, LpgTelemetry, PantryTelemetry, PestEvent

from app.db.mongo import get_db
from app.mqtt.router import router


async def test_mqtt_messages_land_in_memory_db() -> None:
    now = datetime.now(timezone.utc)
    await router.handle(
        "kitchenguard/lpg/lpg01/telemetry",
        LpgTelemetry(device_id="lpg01", ts=now, seq=1, ppm_raw=100, temp_c=28, rh_pct=70, fan_on=False, window_frac=0, edge_tier="Safe", edge_offline_mode=False).model_dump_json().encode(),
    )
    await router.handle(
        "kitchenguard/pantry/pantry-banana01/telemetry",
        PantryTelemetry(device_id="pantry-banana01", compartment="banana", ts=now, mq3_ppm=12, mq135_ppm=22, temp_c=25, rh_pct=64).model_dump_json().encode(),
    )
    await router.handle(
        "kitchenguard/pest/pest-kitchen01/event",
        PestEvent(device_id="pest-kitchen01", ts=now, zone="Sink", trigger_source="Camera", pir=True, vib_rms_g=0.2, vib_trigger=True, ambient_lux=5, camera_in_view=True, yolo_pred="rat", yolo_conf=0.8).model_dump_json().encode(),
    )
    await router.handle(
        "kitchenguard/child/child-cam01/event",
        ChildEvent(device_id="child-cam01", ts=now, w=640, h=480, persons=[], hazards=[], poses=[]).model_dump_json().encode(),
    )
    db = get_db()
    assert await db["telemetry_lpg"].find_one({"device_id": "lpg01"})
    assert await db["telemetry_pantry"].find_one({"device_id": "pantry-banana01"})
    assert await db["pest_events"].find_one({"device_id": "pest-kitchen01"})
    assert await db["child_events"].find_one({"device_id": "child-cam01"})
