from __future__ import annotations

from datetime import datetime, timezone

from kitchenguard_schemas import (
    ActuatorCommand,
    Alert,
    BoxDet,
    ChildEvent,
    ChildRiskPrediction,
    DeterrenceTrial,
    LpgFeatures,
    LpgPrediction,
    LpgTelemetry,
    PantryPrediction,
    PantryTelemetry,
    PestEvent,
)


def test_schema_json_round_trips() -> None:
    now = datetime.now(timezone.utc)
    samples = [
        ActuatorCommand(device_id="lpg01", component="lpg", action="fan", value=1, source="manual", ts=now),
        Alert(alert_id="a1", component="lpg", device_id="lpg01", severity="critical", message="Leak", ts=now),
        LpgTelemetry(device_id="lpg01", ts=now, seq=1, ppm_raw=99, temp_c=28, rh_pct=70, fan_on=False, window_frac=0, edge_tier="Safe", edge_offline_mode=False),
        LpgFeatures(ppm_comp=99, d_ppm_5s=0, slope_30s=0, ma10=99, ma30=99, d_rh_10s=0, tt700_s=3600),
        LpgPrediction(cloud_tier="Safe", source="rule_fallback"),
        PantryTelemetry(device_id="pantry-banana01", compartment="banana", ts=now, mq3_ppm=10, mq135_ppm=20, temp_c=25, rh_pct=60),
        PantryPrediction(freshness_score=100, rsl_h=999, stage="Fresh", source="rule_fallback"),
        PestEvent(device_id="pest-kitchen01", ts=now, zone="Sink", trigger_source="PIR", pir=True, vib_rms_g=0.1, vib_trigger=False, ambient_lux=5, camera_in_view=False),
        DeterrenceTrial(trial_id="t1", device_id="pest-kitchen01", species="rat", condition="control", zone="Sink", activation_s=10, observation_window_s=60, ts=now),
        ChildEvent(device_id="child-cam01", ts=now, w=640, h=480, persons=[BoxDet(cls="child", conf=0.9, box=[0, 0, 0.2, 0.8])], hazards=[], poses=[]),
        ChildRiskPrediction(risk_level="Safe", danger_prob=0.1, source="rule_fallback"),
    ]
    for sample in samples:
        assert sample.__class__.model_validate_json(sample.model_dump_json()) == sample
