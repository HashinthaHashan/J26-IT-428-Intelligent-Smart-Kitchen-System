from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import Field

from .common import ContractModel

HAZARD_CLASSES = Literal[
    "knife",
    "scissors",
    "gas_stove",
    "oven",
    "microwave",
    "kettle",
    "cookware",
    "toaster",
    "blender",
    "power_socket",
    "bottle_chemical",
    "glassware",
]


class BoxDet(ContractModel):
    cls: str
    conf: float
    box: list[float] = Field(min_length=4, max_length=4)


class ChildEvent(ContractModel):
    schema_version: int = 1
    device_id: str
    ts: datetime
    w: int
    h: int
    persons: list[BoxDet]
    hazards: list[BoxDet]
    poses: list[list[list[float]]]


class ChildRiskPrediction(ContractModel):
    risk_level: Literal["Safe", "Warning", "Danger"]
    danger_prob: float
    source: Literal["fusion_model", "rule_fallback"]
