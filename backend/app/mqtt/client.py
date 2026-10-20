from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Awaitable, Callable
from typing import Any

import aiomqtt

from app.core.config import Settings

log = logging.getLogger(__name__)
MessageHandler = Callable[[str, bytes], Awaitable[None]]


class MqttService:
    def __init__(self, settings: Settings, handler: MessageHandler) -> None:
        self.settings = settings
        self.handler = handler
        self.client: aiomqtt.Client | None = None
        self.task: asyncio.Task | None = None

    async def start(self) -> None:
        self.task = asyncio.create_task(self._run(), name="mqtt-service")

    async def stop(self) -> None:
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass

    async def publish_json(self, topic: str, payload: dict[str, Any], qos: int = 1) -> None:
        if self.client is None:
            log.warning("MQTT publish skipped because client is not connected: %s", topic)
            return
        await self.client.publish(topic, json.dumps(payload, default=str), qos=qos)

    async def _run(self) -> None:
        while True:
            try:
                async with aiomqtt.Client(
                    hostname=self.settings.mqtt_host,
                    port=self.settings.mqtt_port,
                    identifier=self.settings.mqtt_client_id,
                ) as client:
                    self.client = client
                    await client.subscribe("kitchenguard/+/+/telemetry", qos=0)
                    await client.subscribe("kitchenguard/+/+/event", qos=1)
                    await client.subscribe("kitchenguard/+/+/status", qos=1)
                    await client.subscribe("kitchenguard/pest/+/capture_request", qos=0)
                    await client.subscribe("kitchenguard/pest/+/capture_done", qos=0)
                    log.info("Connected to MQTT broker %s:%s", self.settings.mqtt_host, self.settings.mqtt_port)
                    async for message in client.messages:
                        await self.handler(str(message.topic), bytes(message.payload))
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001
                self.client = None
                log.warning("MQTT loop failed (%s); retrying in 3s", exc)
                await asyncio.sleep(3)
