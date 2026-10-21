from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from typing import Any

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

from app.core.config import Settings


class MemoryCollection:
    def __init__(self) -> None:
        self.docs: list[dict[str, Any]] = []

    async def insert_one(self, doc: dict[str, Any]) -> Any:
        stored = dict(doc)
        stored.setdefault("_id", len(self.docs) + 1)
        self.docs.append(stored)
        return type("InsertOneResult", (), {"inserted_id": stored["_id"]})()

    async def find_one(self, filt: dict[str, Any], sort: list[tuple[str, int]] | None = None) -> dict[str, Any] | None:
        rows = [d for d in self.docs if _matches(d, filt)]
        if sort:
            for key, direction in reversed(sort):
                rows.sort(key=lambda d: _get(d, key), reverse=direction < 0)
        return dict(rows[0]) if rows else None

    def find(self, filt: dict[str, Any] | None = None) -> "MemoryCursor":
        return MemoryCursor([dict(d) for d in self.docs if _matches(d, filt or {})])

    async def update_one(self, filt: dict[str, Any], update: dict[str, Any], upsert: bool = False) -> Any:
        doc = await self.find_one(filt)
        if doc is None and upsert:
            doc = dict(filt)
            self.docs.append(doc)
        if doc is not None:
            if "$set" in update:
                for key, value in update["$set"].items():
                    _set(doc, key, value)
            if "$setOnInsert" in update and doc not in self.docs:
                for key, value in update["$setOnInsert"].items():
                    _set(doc, key, value)
            for idx, existing in enumerate(self.docs):
                if existing.get("_id") == doc.get("_id") or _matches(existing, filt):
                    self.docs[idx] = doc
                    break
        return type("UpdateResult", (), {"modified_count": 1 if doc else 0})()

    async def create_index(self, *args: Any, **kwargs: Any) -> None:
        return None


class MemoryCursor:
    def __init__(self, rows: list[dict[str, Any]]) -> None:
        self.rows = rows

    def sort(self, key: str, direction: int) -> "MemoryCursor":
        self.rows.sort(key=lambda d: _get(d, key), reverse=direction < 0)
        return self

    def limit(self, n: int) -> "MemoryCursor":
        self.rows = self.rows[:n]
        return self

    def __aiter__(self) -> "MemoryCursor":
        self._i = 0
        return self

    async def __anext__(self) -> dict[str, Any]:
        if self._i >= len(self.rows):
            raise StopAsyncIteration
        row = self.rows[self._i]
        self._i += 1
        return row


class MemoryDB(defaultdict):
    def __init__(self) -> None:
        super().__init__(MemoryCollection)


client: AsyncIOMotorClient | None = None
db: AsyncIOMotorDatabase | MemoryDB | None = None


async def connect(settings: Settings) -> None:
    global client, db
    if settings.use_memory_db:
        db = MemoryDB()
        return
    client = AsyncIOMotorClient(settings.mongo_url)
    db = client[settings.mongo_db]
    await create_indexes()


async def close() -> None:
    global client, db
    if client:
        client.close()
    client = None
    db = None


def get_db() -> AsyncIOMotorDatabase | MemoryDB:
    if db is None:
        raise RuntimeError("Database is not connected")
    return db


async def create_indexes() -> None:
    database = get_db()
    for name in [
        "telemetry_lpg",
        "telemetry_pantry",
        "pest_events",
        "child_events",
        "deterrence_trials",
        "actuator_log",
        "alerts",
    ]:
        await database[name].create_index([("device_id", 1), ("ts", -1)])
        await database[name].create_index([("ts", -1)])
    await database["devices"].create_index("device_id", unique=True)


async def mark_seen(device_id: str, component: str, status: str = "online") -> datetime:
    now = datetime.now(timezone.utc)
    await get_db()["devices"].update_one(
        {"device_id": device_id},
        {"$set": {"device_id": device_id, "component": component, "last_seen": now, "status": status, "meta": {}}},
        upsert=True,
    )
    return now


def serializable(doc: dict[str, Any] | None) -> dict[str, Any] | None:
    if doc is None:
        return None
    return {k: v for k, v in doc.items() if k != "_id"}


def _matches(doc: dict[str, Any], filt: dict[str, Any]) -> bool:
    for key, expected in filt.items():
        value = _get(doc, key)
        if isinstance(expected, dict):
            if "$gte" in expected and not (value >= expected["$gte"]):
                return False
            if "$lte" in expected and not (value <= expected["$lte"]):
                return False
        elif value != expected:
            return False
    return True


def _get(doc: dict[str, Any], dotted: str) -> Any:
    value: Any = doc
    for part in dotted.split("."):
        if not isinstance(value, dict):
            return None
        value = value.get(part)
    return value


def _set(doc: dict[str, Any], dotted: str, value: Any) -> None:
    target = doc
    parts = dotted.split(".")
    for part in parts[:-1]:
        target = target.setdefault(part, {})
    target[parts[-1]] = value
