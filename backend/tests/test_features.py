from __future__ import annotations

from datetime import datetime, timedelta, timezone

from kitchenguard_schemas import LpgTelemetry

from app.services.lpg_features import compute_features


def test_lpg_feature_arithmetic() -> None:
    start = datetime.now(timezone.utc)
    history = [
        LpgTelemetry(
            device_id="lpg01",
            ts=start + timedelta(seconds=i),
            seq=i,
            ppm_raw=100 + i * 10,
            temp_c=28,
            rh_pct=60 + i,
            fan_on=False,
            window_frac=0,
            edge_tier="Safe",
            edge_offline_mode=False,
        )
        for i in range(31)
    ]
    features = compute_features(history)
    assert features.ppm_comp == 400
    assert features.d_ppm_5s == 10
    assert features.slope_30s == 10
    assert features.ma10 == 355
    assert features.ma30 == 255
    assert features.d_rh_10s == 1
    assert features.tt700_s == 30
