from __future__ import annotations

import argparse
import asyncio
import json
from collections.abc import AsyncIterator
from datetime import datetime, timezone
from typing import Any

import aiomqtt
from pydantic import BaseModel


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def parser(description: str) -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=description)
    p.add_argument("--host", default="localhost")
    p.add_argument("--port", type=int, default=1883)
    p.add_argument("--speed", type=float, default=1.0)
    return p


async def mqtt_client(host: str, port: int, client_id: str) -> AsyncIterator[aiomqtt.Client]:
    async with aiomqtt.Client(hostname=host, port=port, identifier=client_id) as client:
        yield client


async def publish_model(client: aiomqtt.Client, topic: str, model: BaseModel, qos: int = 0) -> None:
    await client.publish(topic, model.model_dump_json(), qos=qos)


async def publish_dict(client: aiomqtt.Client, topic: str, payload: dict[str, Any], qos: int = 0) -> None:
    await client.publish(topic, json.dumps(payload, default=str), qos=qos)


def sleep_for(seconds: float, speed: float) -> float:
    return seconds / max(speed, 0.01)


def pose_stub(x: float, y: float) -> list[list[float]]:
    return [[min(max(x + i * 0.003, 0), 1), min(max(y + i * 0.002, 0), 1), 0.8] for i in range(17)]
