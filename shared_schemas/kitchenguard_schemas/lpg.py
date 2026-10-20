from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import Field

from .common import ContractModel

LpgTier = Literal["Safe", "Warning", "Dangerous", "Critical"]


class LpgTelemetry(ContractModel):
    schema_version: int = 1
    device_id: str
    ts: datetime
    seq: int
    ppm_raw: float
    temp_c: float
    rh_pct: float
    fan_on: bool
    window_frac: float = Field(ge=0.0, le=1.0)
    edge_tier: LpgTier
    edge_offline_mode: bool


class LpgFeatures(ContractModel):
    ppm_comp: float
    d_ppm_5s: float
    slope_30s: float
    ma10: float
    ma30: float
    d_rh_10s: float
    tt700_s: float


class LpgPrediction(ContractModel):
    cloud_tier: LpgTier
    source: Literal["model", "rule_fallback", "safety_override"]
    confidence: float | None = None
