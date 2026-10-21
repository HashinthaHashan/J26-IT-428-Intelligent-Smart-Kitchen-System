from __future__ import annotations

import json
import os
import time
import uuid
from datetime import datetime, timezone
from typing import Any

import logging

from pydantic import ValidationError

from kitchenguard_schemas import (
    ActuatorCommand,
    Alert,
    ChildEvent,
    DeterrenceTrial,
    LpgTelemetry,
    PantryTelemetry,
    PestEvent,
)

from app.api.ws import hub
from app.db.mongo import mark_seen
from app.db.repositories import insert
from app.services.child_fusion import predict as predict_child
from app.services.inference import get_registry
from app.services.lpg_features import push_and_compute
from app.services.pantry_features import push_and_compute as pantry_features
from app.services.pest_logic import is_pest_warning
from app.services.pest_pipeline import coordinator


log = logging.getLogger(__name__)

ALERT_COOLDOWN_S = float(os.getenv("ALERT_COOLDOWN_S", "300"))
_SEVERITY_RANK = {"info": 0, "warning": 1, "danger": 2, "critical": 3}


class MqttRouter:
    def __init__(self) -> None:
        self.publisher: Any | None = None
        self._last_alert: dict[tuple[str, str], tuple[str, float]] = {}

    def set_publisher(self, publisher: Any) -> None:
        self.publisher = publisher

    async def handle(self, topic: str, payload: bytes) -> None:
        component, device_id, channel = parse_topic(topic)
        if channel == "status":
            status = json.loads(payload.decode()).get("status", "online")
            last_seen = await mark_seen(device_id, component, status=status)
            await hub.publish(
                "device_status",
                {
                    "device_id": device_id,
                    "component": component,
                    "status": status,
                    "last_seen": last_seen,
                },
            )
            return
        if component == "lpg" and channel == "telemetry":
            await self._lpg(device_id, payload)
        elif component == "pantry" and channel == "telemetry":
            await self._pantry(device_id, payload)
        elif component == "pest" and channel == "event":
            await self._pest(device_id, payload)
        elif component == "pest" and channel == "capture_request":
            await coordinator.on_capture_request(self, payload)
        elif component == "pest" and channel == "capture_done":
            await coordinator.on_capture_done(payload)
        elif component == "child" and channel == "event":
            await self._child(device_id, payload)

    async def publish_command(self, command: ActuatorCommand) -> None:
        await insert("actuator_log", command.model_dump(mode="json"))
        # One line per command so "did the backend send it, and with what value?"
        # is answered from this log alone.
        log.info(
            "cmd -> kitchenguard/%s/%s/cmd action=%s value=%s source=%s publisher=%s",
            command.component, command.device_id, command.action, command.value,
            command.source, "ready" if self.publisher else "MISSING (not published!)",
        )
        if self.publisher:
            await self.publisher.publish_json(
                f"kitchenguard/{command.component}/{command.device_id}/cmd",
                command.model_dump(mode="json"),
                qos=1,
            )
        await hub.publish("cmd", command.model_dump(mode="json"))

    async def _lpg(self, device_id: str, payload: bytes) -> None:
        msg = LpgTelemetry.model_validate_json(payload)
        _assert_device_id(device_id, msg.device_id)
        await mark_seen(msg.device_id, "lpg")
        features = push_and_compute(msg)
        prediction = get_registry().predict_lpg(features)
        doc = {
            "device_id": msg.device_id,
            "ts": msg.ts,
            "raw": msg.model_dump(mode="json"),
            "features": features.model_dump(mode="json"),
            "prediction": prediction.model_dump(mode="json"),
        }
        await insert("telemetry_lpg", doc)
        await hub.publish("lpg", doc)
        if prediction.cloud_tier in {"Dangerous", "Critical"}:
            severity = "critical" if prediction.cloud_tier == "Critical" else "danger"
            await self._alert("lpg", msg.device_id, severity, f"LPG tier {prediction.cloud_tier}", doc)
            if prediction.cloud_tier == "Critical":
                await self.publish_command(
                    ActuatorCommand(
                        device_id=msg.device_id,
                        component="lpg",
                        action="fan",
                        value=1,
                        source="override",
                        ts=datetime.now(timezone.utc),
                    )
                )

    async def _pantry(self, device_id: str, payload: bytes) -> None:
        msg = PantryTelemetry.model_validate_json(payload)
        _assert_device_id(device_id, msg.device_id)
        await mark_seen(msg.device_id, "pantry")
        features = pantry_features(msg)
        prediction = get_registry().predict_pantry(msg, features)
        doc = {
            "device_id": msg.device_id,
            "compartment": msg.compartment,
            "ts": msg.ts,
            "raw": msg.model_dump(mode="json"),
            "features": features,
            "prediction": prediction.model_dump(mode="json"),
        }
        await insert("telemetry_pantry", doc)
        await hub.publish("pantry", doc)
        if prediction.stage == "Spoiled" or prediction.rsl_h < 24:
            await self._alert("pantry", msg.device_id, "warning", f"{msg.compartment} needs attention", doc, key_suffix=f"/{msg.compartment}")

    async def _pest(self, device_id: str, payload: bytes) -> None:
        data = json.loads(payload)
        if "trial_id" in data:
            trial = DeterrenceTrial.model_validate(data)
            _assert_device_id(device_id, trial.device_id)
            await mark_seen(trial.device_id, "pest")
            doc = trial.model_dump(mode="json")
            await insert("deterrence_trials", doc)
            await hub.publish("deterrence_trial", doc)
            return
        event = PestEvent.model_validate(data)
        _assert_device_id(device_id, event.device_id)
        await mark_seen(event.device_id, "pest")
        doc = {"device_id": event.device_id, "ts": event.ts, "event": event.model_dump(mode="json")}
        await insert("pest_events", doc)
        await hub.publish("pest", doc)
        # A photo can be classified before its (possibly queued) event arrives.
        await coordinator.apply_unmatched(self, event.device_id, event)
        if is_pest_warning(event):
            await self._alert("pest", event.device_id, "warning", f"Pest detected: {event.yolo_pred}", doc)

    async def _child(self, device_id: str, payload: bytes) -> None:
        event = ChildEvent.model_validate_json(payload)
        _assert_device_id(device_id, event.device_id)
        await mark_seen(event.device_id, "child")
        prediction = predict_child(event)
        doc = {
            "device_id": event.device_id,
            "ts": event.ts,
            "event": event.model_dump(mode="json"),
            "prediction": prediction.model_dump(mode="json"),
        }
        await insert("child_events", doc)
        await hub.publish("child", doc)
        if prediction.risk_level == "Danger":
            await self._alert("child", event.device_id, "critical", "Child in danger zone", doc)

    async def _alert(self, component: str, device_id: str, severity: str, message: str, data: dict, key_suffix: str = "") -> None:
        # Telemetry arrives every second or so; an ongoing condition must not
        # raise a new alert each time. Repeat alerts are suppressed for a
        # cooldown unless the same device escalates to a higher severity.
        # key_suffix lets one device raise independent alerts (e.g. the pantry's banana
        # and potato compartments share a device_id but must not mute each other).
        key = (component, device_id + key_suffix)
        now = time.monotonic()
        last = self._last_alert.get(key)
        if last is not None:
            last_severity, last_at = last
            escalated = _SEVERITY_RANK.get(severity, 0) > _SEVERITY_RANK.get(last_severity, 0)
            if not escalated and now - last_at < ALERT_COOLDOWN_S:
                return
        self._last_alert[key] = (severity, now)
        alert = Alert(
            alert_id=str(uuid.uuid4()),
            component=component,
            device_id=device_id,
            severity=severity,
            message=message,
            data=data,
            ts=datetime.now(timezone.utc),
        )
        doc = alert.model_dump(mode="json")
        await insert("alerts", doc)
        await hub.publish("alert", doc)


router = MqttRouter()


def parse_topic(topic: str) -> tuple[str, str, str]:
    parts = topic.split("/")
    if len(parts) != 4 or parts[0] != "kitchenguard":
        raise ValueError(f"Invalid MQTT topic: {topic}")
    return parts[1], parts[2], parts[3]


def _assert_device_id(topic_device_id: str, payload_device_id: str) -> None:
    if topic_device_id != payload_device_id:
        raise ValueError(f"topic device_id {topic_device_id} does not match payload {payload_device_id}")
