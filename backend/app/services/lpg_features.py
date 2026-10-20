from __future__ import annotations

from collections import defaultdict, deque

from kitchenguard_schemas import LpgFeatures, LpgTelemetry

FEATURE_ORDER = ["ppm_comp", "d_ppm_5s", "slope_30s", "ma10", "ma30", "d_rh_10s", "tt700_s"]

# Phase 0 state is intentionally simple and resets on restart; move to Mongo/Redis before production.
_history: dict[str, deque[LpgTelemetry]] = defaultdict(lambda: deque(maxlen=31))


def push_and_compute(sample: LpgTelemetry) -> LpgFeatures:
    buf = _history[sample.device_id]
    buf.append(sample)
    return compute_features(list(buf))


def compute_features(history: list[LpgTelemetry]) -> LpgFeatures:
    if not history:
        raise ValueError("history must contain at least one LPG sample")
    ppm = [x.ppm_raw for x in history]
    rh = [x.rh_pct for x in history]
    last_ppm = ppm[-1]
    # TODO: apply MQ-2 T/RH compensation once calibrated.
    ppm_comp = last_ppm
    d_ppm_5s = (ppm[-1] - ppm[-6]) / 5 if len(ppm) >= 6 else 0.0
    slope_30s = (ppm[-1] - ppm[-31]) / 30 if len(ppm) >= 31 else 0.0
    ma10 = sum(ppm[-10:]) / min(len(ppm), 10)
    ma30 = sum(ppm[-30:]) / min(len(ppm), 30)
    d_rh_10s = (rh[-1] - rh[-11]) / 10 if len(rh) >= 11 else 0.0
    tt700_s = min(max((700 - last_ppm) / max(slope_30s, 0.05), 0), 3600) if slope_30s > 0.05 else 3600.0
    return LpgFeatures(
        ppm_comp=ppm_comp,
        d_ppm_5s=d_ppm_5s,
        slope_30s=slope_30s,
        ma10=ma10,
        ma30=ma30,
        d_rh_10s=d_rh_10s,
        tt700_s=tt700_s,
    )
