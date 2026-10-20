from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.api.auth import require_dev_token
from app.db.repositories import latest

router = APIRouter(prefix="/api/child", tags=["child"], dependencies=[Depends(require_dev_token)])


@router.get("/{device_id}/latest")
async def latest_child(device_id: str) -> dict:
    doc = await latest("child_events", device_id)
    if not doc:
        raise HTTPException(404, "No child event for device")
    return doc
