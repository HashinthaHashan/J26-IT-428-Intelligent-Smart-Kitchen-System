from __future__ import annotations

from collections import defaultdict, deque

from kitchenguard_schemas import PantryTelemetry

# Phase 0 state is intentionally simple and resets on restart; move to Mongo/Redis before production.
_history: dict[tuple[str, str], deque[PantryTelemetry]] = defaultdict(lambda: deque(maxlen=1440))
_deg_hours: dict[tuple[str, str], float] = defaultdict(float)


def push_and_compute(sample: PantryTelemetry) -> dict[str, float]:
    key = (sample.device_id, sample.compartment)
    buf = _history[key]
    buf.append(sample)
    mass = sample.mass_kg or 1.0
    _deg_hours[key] += max(sample.temp_c - 13, 0) / 60.0
    mq3 = [x.mq3_ppm for x in buf]
    mq135 = [x.mq135_ppm for x in buf]
    temp = [x.temp_c for x in buf]
    rh = [x.rh_pct for x in buf]
    return {
        "mq3_ppm_per_kg": sample.mq3_ppm / mass,
        "mq3_ppm_d6h": mq3[-1] - mq3[-360] if len(mq3) >= 360 else 0.0,
        "mq3_ppm_ma12": sum(mq3[-12:]) / min(len(mq3), 12),
        "mq135_ppm_per_kg": sample.mq135_ppm / mass,
        "mq135_ppm_d6h": mq135[-1] - mq135[-360] if len(mq135) >= 360 else 0.0,
        "mq135_ppm_ma12": sum(mq135[-12:]) / min(len(mq135), 12),
        "temp_ma24": sum(temp[-24:]) / min(len(temp), 24),
        "rh_ma24": sum(rh[-24:]) / min(len(rh), 24),
        "deg_hours": _deg_hours[key],
    }
