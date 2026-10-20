from __future__ import annotations

from fastapi import APIRouter, Depends

from app.api.auth import require_dev_token
from app.db.repositories import list_devices

router = APIRouter(prefix="/api/devices", tags=["devices"], dependencies=[Depends(require_dev_token)])


@router.get("")
async def devices() -> list[dict]:
    return await list_devices()
