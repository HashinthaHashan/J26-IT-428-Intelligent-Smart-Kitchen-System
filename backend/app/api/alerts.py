from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from app.api.auth import require_dev_token
from app.db.mongo import get_db, serializable

router = APIRouter(prefix="/api/alerts", tags=["alerts"], dependencies=[Depends(require_dev_token)])


@router.get("")
async def alerts(acknowledged: bool | None = None) -> list[dict]:
    filt = {} if acknowledged is None else {"acknowledged": acknowledged}
    rows = get_db()["alerts"].find(filt).sort("ts", -1).limit(200)
    return [serializable(row) async for row in rows]


@router.post("/{alert_id}/ack")
async def ack(alert_id: str) -> dict:
    result = await get_db()["alerts"].update_one({"alert_id": alert_id}, {"$set": {"acknowledged": True}})
    if result.modified_count == 0:
        raise HTTPException(404, "Alert not found")
    return {"alert_id": alert_id, "acknowledged": True}
