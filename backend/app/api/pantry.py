from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.api.auth import require_dev_token
from app.db.repositories import history, latest

router = APIRouter(prefix="/api/pantry", tags=["pantry"], dependencies=[Depends(require_dev_token)])


@router.get("/{device_id}/latest")
async def latest_pantry(device_id: str, compartment: str = "banana") -> dict:
    doc = await latest("telemetry_pantry", device_id, {"compartment": compartment})
    if not doc:
        raise HTTPException(404, "No pantry telemetry for device")
    return doc


@router.get("/{device_id}/history")
async def pantry_history(
    device_id: str,
    compartment: str = "banana",
    minutes: int = 1440,
    limit: int = 1500,
) -> list[dict]:
    """Readings of one compartment, newest first (same shape as /latest)."""
    return await history(
        "telemetry_pantry",
        device_id,
        minutes=min(max(minutes, 1), 10080),
        limit=min(max(limit, 1), 3000),
        extra_filter={"compartment": compartment},
    )
