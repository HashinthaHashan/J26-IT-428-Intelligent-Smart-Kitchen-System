from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from kitchenguard_schemas import ActuatorCommand

from app.api.auth import require_dev_token
from app.db.repositories import history, latest
from app.mqtt.router import router as mqtt_router

router = APIRouter(prefix="/api/lpg", tags=["lpg"], dependencies=[Depends(require_dev_token)])


class CommandIn(BaseModel):
    action: str
    value: float


@router.get("/{device_id}/latest")
async def latest_lpg(device_id: str) -> dict:
    doc = await latest("telemetry_lpg", device_id)
    if not doc:
        raise HTTPException(404, "No LPG telemetry for device")
    return doc


@router.get("/{device_id}/history")
async def lpg_history(device_id: str, minutes: int = 60) -> list[dict]:
    return await history("telemetry_lpg", device_id, minutes)


@router.post("/{device_id}/cmd")
async def lpg_cmd(device_id: str, body: CommandIn, user_id: str = Depends(require_dev_token)) -> dict:
    command = ActuatorCommand(
        device_id=device_id,
        component="lpg",
        action=body.action,
        value=body.value,
        source="manual",
        issued_by=user_id,
        ts=datetime.now(timezone.utc),
    )
    await mqtt_router.publish_command(command)
    return command.model_dump(mode="json")
