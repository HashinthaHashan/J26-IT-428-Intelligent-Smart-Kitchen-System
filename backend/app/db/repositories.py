from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from app.db.mongo import get_db, serializable


async def insert(collection: str, doc: dict[str, Any]) -> dict[str, Any]:
    await get_db()[collection].insert_one(doc)
    return doc


async def latest(collection: str, device_id: str, extra: dict[str, Any] | None = None) -> dict[str, Any] | None:
    filt = {"device_id": device_id}
    if extra:
        filt.update(extra)
    return serializable(await get_db()[collection].find_one(filt, sort=[("ts", -1)]))


async def history(
    collection: str,
    device_id: str,
    minutes: int = 60,
    limit: int = 500,
    extra_filter: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    since = datetime.now(timezone.utc) - timedelta(minutes=minutes)
    query = {"device_id": device_id, "ts": {"$gte": since}, **(extra_filter or {})}
    rows = get_db()[collection].find(query).sort("ts", -1).limit(limit)
    return [serializable(row) async for row in rows]


async def list_devices() -> list[dict[str, Any]]:
    rows = get_db()["devices"].find({}).sort("device_id", 1)
    # The in-memory preview can receive a retained status and telemetry in the
    # same event-loop tick. Collapse any racing upserts so the app always gets
    # one authoritative, newest row per physical device.
    newest: dict[tuple[str, str], dict[str, Any]] = {}
    async for row in rows:
        clean = serializable(row)
        if clean is None:
            continue
        key = (str(clean.get("component", "")), str(clean.get("device_id", "")))
        previous = newest.get(key)
        if previous is None or clean.get("last_seen") >= previous.get("last_seen"):
            newest[key] = clean
    return sorted(newest.values(), key=lambda row: (row.get("component", ""), row.get("device_id", "")))
