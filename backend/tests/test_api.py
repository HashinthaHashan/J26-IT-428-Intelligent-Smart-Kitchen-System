from __future__ import annotations

from datetime import datetime, timezone

from fastapi.testclient import TestClient
from kitchenguard_schemas import Alert, ChildEvent, DeterrenceTrial, LpgTelemetry, PantryTelemetry, PestEvent

from app.main import app
from app.db.repositories import insert
from app.mqtt.router import router


async def seed() -> str:
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
        PestEvent(device_id="pest-kitchen01", ts=now, zone="Sink", trigger_source="PIR", pir=True, vib_rms_g=0.2, vib_trigger=True, ambient_lux=5, camera_in_view=False).model_dump_json().encode(),
    )
    await router.handle(
        "kitchenguard/child/child-cam01/event",
        ChildEvent(device_id="child-cam01", ts=now, w=640, h=480, persons=[], hazards=[], poses=[]).model_dump_json().encode(),
    )
    await insert("deterrence_trials", DeterrenceTrial(trial_id="trial1", device_id="pest-kitchen01", species="rat", condition="control", zone="Sink", activation_s=10, observation_window_s=60, ts=now).model_dump(mode="json"))
    alert = Alert(alert_id="alert1", component="lpg", device_id="lpg01", severity="warning", message="test", ts=now)
    await insert("alerts", alert.model_dump(mode="json"))
    return alert.alert_id


async def test_api_routes_200_and_404(api_client) -> None:
    alert_id = await seed()
    assert (await api_client.get("/api/devices")).status_code == 200
    assert (await api_client.get("/api/lpg/lpg01/latest")).status_code == 200
    assert (await api_client.get("/api/lpg/missing/latest")).status_code == 404
    assert (await api_client.get("/api/lpg/lpg01/history?minutes=60")).status_code == 200
    assert (await api_client.post("/api/lpg/lpg01/cmd", json={"action": "fan", "value": 1})).status_code == 200
    assert (await api_client.post("/api/lpg/lpg01/cmd", json={"action": "fan"})).status_code == 422
    assert (await api_client.get("/api/pantry/pantry-banana01/latest?compartment=banana")).status_code == 200
    assert (await api_client.get("/api/pantry/pantry-banana01/latest?compartment=potato")).status_code == 404
    assert (await api_client.get("/api/pest/pest-kitchen01/events?limit=50")).status_code == 200
    assert (await api_client.post("/api/pest/pest-kitchen01/trials/trial1/review", json={"manual_verdict": "left"})).status_code == 200
    assert (await api_client.post("/api/pest/pest-kitchen01/trials/missing/review", json={"manual_verdict": "left"})).status_code == 404
    assert (await api_client.get("/api/child/child-cam01/latest")).status_code == 200
    assert (await api_client.get("/api/child/missing/latest")).status_code == 404
    assert (await api_client.get("/api/alerts?acknowledged=false")).status_code == 200
    assert (await api_client.post(f"/api/alerts/{alert_id}/ack")).status_code == 200
    assert (await api_client.post("/api/alerts/missing/ack")).status_code == 404


async def test_auth_required(api_client) -> None:
    api_client.headers.pop("Authorization")
    assert (await api_client.get("/api/devices")).status_code == 401


def test_websocket_endpoint_connects() -> None:
    client = TestClient(app)
    with client.websocket_connect("/ws/live") as websocket:
        websocket.send_text("ping")
