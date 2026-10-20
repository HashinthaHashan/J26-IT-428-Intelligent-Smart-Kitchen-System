from __future__ import annotations

from datetime import datetime, timezone

from kitchenguard_schemas import PantryTelemetry

from app.db.mongo import get_db
from app.mqtt.router import MqttRouter
from app.services.pantry_rules import rule_prediction, sensor_score, stage_for

TOPIC = "kitchenguard/pantry/pantry01/telemetry"


def _msg(compartment: str, mq3: float, mq135: float) -> bytes:
    """What the sensor board publishes: camera/mass fields are null."""
    return PantryTelemetry(
        device_id="pantry01",
        compartment=compartment,
        ts=datetime.now(timezone.utc),
        mq3_ppm=mq3,
        mq135_ppm=mq135,
        temp_c=26.7,
        rh_pct=43.2,
    ).model_dump_json().encode()


def _tel(mq3: float, mq135: float) -> PantryTelemetry:
    return PantryTelemetry.model_validate_json(_msg("banana", mq3, mq135))


def test_sensor_score_hits_the_literature_anchors():
    assert sensor_score(0, 81, 108) == 100
    assert sensor_score(81, 81, 108) == 60  # ethanol "ripe" anchor
    assert sensor_score(108, 81, 108) == 0  # ethanol "decomposed" anchor
    assert sensor_score(48, 48, 111) == 60  # ammonia "ripe" anchor
    assert sensor_score(111, 48, 111) == 0  # ammonia "decomposed" anchor
    assert sensor_score(500, 81, 108) == 0  # stays at 0 above decomposed


def test_prediction_uses_the_worse_sensor_and_is_not_the_old_constant():
    clean = rule_prediction(_tel(0.4, 4.3))
    assert clean.stage == "Fresh" and clean.freshness_score > 90
    assert clean.source == "rule_fallback"
    # ethanol is fine but ammonia is at its ripe anchor -> Ripe
    ripe = rule_prediction(_tel(1.0, 48.0))
    assert ripe.stage == "Ripe" and ripe.freshness_score == 60.0
    # either sensor at its decomposed anchor -> Spoiled, no shelf life left
    spoiled = rule_prediction(_tel(120.0, 5.0))
    assert spoiled.stage == "Spoiled" and spoiled.rsl_h == 0.0
    # 100 -> one week of shelf life
    assert rule_prediction(_tel(0.0, 0.0)).rsl_h == 168.0


def test_stage_boundaries():
    assert [stage_for(s) for s in (100, 75, 74.9, 40, 39.9, 15, 14.9, 0)] == [
        "Fresh", "Fresh", "Ripe", "Ripe", "Deteriorating", "Deteriorating", "Spoiled", "Spoiled",
    ]


async def test_one_device_two_compartments_are_stored_and_served_independently(api_client):
    router = MqttRouter()
    # Sensor board behaviour: the SAME reading, once per compartment.
    await router.handle(TOPIC, _msg("banana", 0.5, 5.0))
    await router.handle(TOPIC, _msg("potato", 0.5, 5.0))

    banana = await api_client.get("/api/pantry/pantry01/latest?compartment=banana")
    potato = await api_client.get("/api/pantry/pantry01/latest?compartment=potato")
    assert banana.status_code == 200 and potato.status_code == 200
    assert banana.json()["raw"]["compartment"] == "banana"
    assert potato.json()["raw"]["compartment"] == "potato"
    for doc in (banana.json(), potato.json()):
        assert doc["raw"]["device_id"] == "pantry01"
        assert doc["prediction"]["stage"] == "Fresh"
        assert doc["prediction"]["freshness_score"] < 100  # not the old constant
        assert doc["prediction"]["rsl_h"] < 999

    docs = [d async for d in get_db()["telemetry_pantry"].find({"device_id": "pantry01"})]
    assert sorted(d["compartment"] for d in docs) == ["banana", "potato"]


async def test_spoiled_reading_alerts_once_per_compartment(api_client):
    router = MqttRouter()
    await router.handle(TOPIC, _msg("banana", 150.0, 150.0))
    await router.handle(TOPIC, _msg("potato", 150.0, 150.0))
    alerts = (await api_client.get("/api/alerts")).json()
    messages = sorted(a["message"] for a in alerts if a["component"] == "pantry")
    # The two compartments share a device_id but must not mute each other.
    assert messages == ["banana needs attention", "potato needs attention"]


async def test_history_is_per_compartment_and_newest_first(api_client):
    router = MqttRouter()
    for mq3 in (0.5, 0.6, 0.7):
        await router.handle(TOPIC, _msg("banana", mq3, 5.0))
    await router.handle(TOPIC, _msg("potato", 9.0, 5.0))

    banana = (await api_client.get("/api/pantry/pantry01/history?compartment=banana&minutes=60")).json()
    potato = (await api_client.get("/api/pantry/pantry01/history?compartment=potato&minutes=60")).json()
    assert [d["raw"]["compartment"] for d in banana] == ["banana"] * 3
    assert [d["raw"]["mq3_ppm"] for d in potato] == [9.0]
    stamps = [d["ts"] for d in banana]
    assert stamps == sorted(stamps, reverse=True)
    # the same shape the app parses for /latest
    assert {"raw", "prediction"} <= set(banana[0])
    assert (await api_client.get("/api/pantry/other-device/history?compartment=banana")).json() == []
