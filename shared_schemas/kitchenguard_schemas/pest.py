from __future__ import annotations

from datetime import datetime
from typing import Literal

from .common import ContractModel

ZONES = Literal["Sink", "Pantry floor", "Trash bin", "Under cabinet", "Behind fridge"]


class PestEvent(ContractModel):
    schema_version: int = 1
    device_id: str
    ts: datetime
    zone: ZONES
    trigger_source: Literal["PIR", "IR", "Vibration", "Camera", "None"]
    pir: bool
    vib_rms_g: float
    vib_trigger: bool
    ambient_lux: float
    camera_in_view: bool
    yolo_pred: Literal["rat", "cockroach", "non_pest", "none", "not_in_view"] | None = None
    yolo_conf: float | None = None


class DeterrenceTrial(ContractModel):
    schema_version: int = 1
    trial_id: str
    device_id: str
    # None = species unknown: the camera answered too late, never, or said non-pest.
    # The deterrent never waits for it: the species is attached to the running trial.
    species: Literal["rat", "cockroach"] | None = None
    condition: str
    zone: ZONES
    activation_s: int
    observation_window_s: int
    exited: bool | None = None
    time_to_leave_s: float | None = None
    system_verdict: Literal["left", "remains", "uncertain"] | None = None
    manual_verdict: Literal["left", "remains"] | None = None
    ts: datetime


class PestCaptureRequest(ContractModel):
    """Board 1 -> backend: please have the camera take a photo for this event."""

    schema_version: int = 1
    device_id: str
    request_id: str
    ts: datetime
    event_ts: datetime  # the PestEvent this photo belongs to (with trigger_source)
    trigger_source: Literal["PIR", "IR", "Vibration", "Camera", "None"]
    zone: ZONES


class PestCaptureDone(ContractModel):
    """Camera board -> backend: the capture finished; was the HTTP upload accepted?"""

    schema_version: int = 1
    device_id: str
    request_id: str
    ts: datetime
    upload_ok: bool
    image_format: Literal["jpeg", "rgb565"] = "jpeg"
    bytes: int = 0
    detail: str | None = None
