from __future__ import annotations

from datetime import datetime
from typing import Literal

from .common import ContractModel

Compartment = Literal["banana", "potato"]


class PantryTelemetry(ContractModel):
    schema_version: int = 1
    device_id: str
    compartment: Compartment
    ts: datetime
    mq3_ppm: float
    mq135_ppm: float
    temp_c: float
    rh_pct: float
    mass_kg: float | None = None
    item_count: int | None = None
    hue_mean: float | None = None
    brown_pct: float | None = None
    green_pct: float | None = None


class PantryPrediction(ContractModel):
    freshness_score: float
    rsl_h: float
    stage: Literal["Fresh", "Ripe", "Deteriorating", "Spoiled"]
    source: Literal["model", "rule_fallback"]
