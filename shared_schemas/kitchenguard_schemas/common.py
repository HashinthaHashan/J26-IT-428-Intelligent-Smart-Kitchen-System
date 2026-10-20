from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

Component = Literal["lpg", "pantry", "pest", "child"]


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ActuatorCommand(ContractModel):
    schema_version: int = 1
    device_id: str
    component: Component
    action: str
    value: float
    source: Literal["manual", "auto", "override"]
    issued_by: str | None = None
    # Optional structured arguments, e.g. a pest "deterrent" command carries
    # {condition, species, confidence, request_id}. LPG commands do not use it.
    params: dict[str, Any] | None = None
    ts: datetime


class Alert(ContractModel):
    schema_version: int = 1
    alert_id: str
    component: Component
    device_id: str
    severity: Literal["info", "warning", "danger", "critical"]
    message: str
    data: dict = Field(default_factory=dict)
    ts: datetime
    acknowledged: bool = False
