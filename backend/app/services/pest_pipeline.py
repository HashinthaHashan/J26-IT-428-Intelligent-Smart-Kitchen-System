"""Ties pest sensor triggers, camera photos and YOLO together.

    Board 1 (sensors)  --capture_request-->  backend  --capture-->  Board 2 (camera)
    Board 2            --HTTP photo-------->  backend  (YOLO)  -->  PestEvent updated
    backend            --cmd (classification)-->  Board 1  (species, attached to its running trial)

The deterrent does NOT wait for any of this: Board 1 starts its trial the instant a
trigger is confirmed and requests the photo in parallel. The classification only
enriches the record afterwards: it fills in the PestEvent here, and is sent to Board 1
so it can attach the species to the trial that is still running.

Why the backend relays the request instead of Board 2 subscribing to Board 1's topic:
the backend has to know about every request anyway (it links the later photo to the
right PestEvent), so it can also log, rate-limit and drop requests, and Board 1 never
needs to know a camera exists. The relay adds only a few milliseconds on a LAN.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Any

from kitchenguard_schemas import ActuatorCommand, PestCaptureDone, PestCaptureRequest, PestEvent

from app.api.ws import hub
from app.db.mongo import get_db, serializable
from app.services.pest_logic import is_pest_warning
from app.services.pest_yolo import PestClassification, get_detector

if TYPE_CHECKING:  # pragma: no cover
    from app.mqtt.router import MqttRouter

log = logging.getLogger(__name__)

PEST_LABELS = {"rat", "cockroach"}


@dataclass
class PendingRequest:
    request_id: str
    device_id: str
    event_ts: datetime
    trigger_source: str
    zone: str
    received_mono: float


def should_send_species(classification: PestClassification | None, threshold: float) -> bool:
    """Whether Board 1 is told this answer (it only attaches rat / cockroach).

    A confident answer (at or above the threshold) is sent; a low-confidence or "nothing
    found" answer is not, so a shaky guess is never written onto a trial. The PestEvent
    always gets the raw result regardless."""
    if classification is None or classification.conf is None:
        return False
    return classification.label in (PEST_LABELS | {"non_pest"}) and classification.conf >= threshold


class PestCoordinator:
    def __init__(self) -> None:
        self.pending: dict[str, PendingRequest] = {}
        # Classifications that arrived before their PestEvent was stored:
        # (device_id, event_ts iso, trigger) -> (label, conf)
        self.unmatched: dict[tuple[str, str, str], tuple[str, float | None]] = {}
        self.conf_threshold = 0.6

    def configure(self, settings: Any) -> None:
        self.conf_threshold = settings.pest_conf_threshold

    def _prune(self) -> None:
        cutoff = time.monotonic() - 300
        for key in [k for k, v in self.pending.items() if v.received_mono < cutoff]:
            self.pending.pop(key, None)
        if len(self.unmatched) > 200:
            self.unmatched.clear()

    # ---- MQTT side -------------------------------------------------------------

    async def on_capture_request(self, router: "MqttRouter", payload: bytes) -> None:
        req = PestCaptureRequest.model_validate_json(payload)
        self._prune()
        self.pending[req.request_id] = PendingRequest(
            request_id=req.request_id,
            device_id=req.device_id,
            event_ts=req.event_ts,
            trigger_source=req.trigger_source,
            zone=req.zone,
            received_mono=time.monotonic(),
        )
        topic = f"kitchenguard/pest/{req.device_id}/capture"
        relayed = {
            "schema_version": 1,
            "device_id": req.device_id,
            "request_id": req.request_id,
            "ts": datetime.now(timezone.utc).isoformat(),
            "event_ts": req.event_ts.isoformat(),
            "trigger_source": req.trigger_source,
            "zone": req.zone,
        }
        if router.publisher is None:
            log.warning("capture request %s not relayed: MQTT publisher is not connected", req.request_id)
            return
        await router.publisher.publish_json(topic, relayed, qos=0)
        log.info("capture request %s (%s, %s) relayed to the camera on %s", req.request_id, req.trigger_source, req.zone, topic)

    async def on_capture_done(self, payload: bytes) -> None:
        done = PestCaptureDone.model_validate_json(payload)
        if done.upload_ok:
            log.info("camera finished %s: uploaded %d bytes (%s)", done.request_id, done.bytes, done.image_format)
        else:
            self.pending.pop(done.request_id, None)
            log.warning("camera could NOT upload %s (%s): this trigger gets no species", done.request_id, done.detail)

    # ---- photo side ------------------------------------------------------------

    async def handle_photo(
        self, router: "MqttRouter", device_id: str, request_id: str | None, jpeg: bytes
    ) -> dict[str, Any]:
        detector = get_detector()
        classification: PestClassification | None = None
        if detector is not None:
            classification = await asyncio.to_thread(detector.classify, jpeg)
        else:
            log.warning("photo received but no YOLO model is loaded: no classification available")

        pending = self.pending.pop(request_id, None) if request_id else None
        elapsed = time.monotonic() - pending.received_mono if pending else 0.0
        result: dict[str, Any] = {
            "label": classification.label if classification else None,
            "confidence": classification.conf if classification else None,
            "inference_ms": round(classification.inference_ms) if classification else None,
            "model_loaded": detector is not None,
            "matched_request": pending is not None,
            "elapsed_s": round(elapsed, 3) if pending else None,
            "event_updated": False,
            "command": "none",
        }
        if pending is None or classification is None:
            return result

        result["event_updated"] = await self._update_event(
            router, pending.device_id, pending.event_ts, pending.trigger_source, classification.label, classification.conf
        )
        if should_send_species(classification, self.conf_threshold):
            command = ActuatorCommand(
                device_id=pending.device_id,
                component="pest",
                action="classification",
                value=1.0,
                source="auto",
                ts=datetime.now(timezone.utc),
                params={
                    "species": classification.label,
                    "confidence": classification.conf,
                    "request_id": pending.request_id,
                },
            )
            await router.publish_command(command)
            result["command"] = "classification"
            log.info(
                "species for %s sent to the device: %s %.2f, %.2fs after the trigger (it attaches it to its running trial)",
                pending.request_id, classification.label, classification.conf or 0.0, elapsed,
            )
        else:
            log.info(
                "species for %s NOT sent (%s, conf %s below %.2f): the event keeps the raw result, the trial stays unidentified",
                pending.request_id, classification.label, classification.conf, self.conf_threshold,
            )
        return result

    # ---- event update ----------------------------------------------------------

    async def _update_event(
        self,
        router: "MqttRouter",
        device_id: str,
        event_ts: datetime,
        trigger: str,
        label: str,
        conf: float | None,
    ) -> bool:
        """Fill in yolo_pred / yolo_conf / camera_in_view on the matching PestEvent."""
        filt = {"device_id": device_id, "ts": event_ts, "event.trigger_source": trigger}
        result = await get_db()["pest_events"].update_one(
            filt,
            {"$set": {"event.yolo_pred": label, "event.yolo_conf": conf, "event.camera_in_view": True}},
        )
        if not result.modified_count:
            # The photo beat the event through the (queued) MQTT path; apply it on arrival.
            self.unmatched[(device_id, event_ts.isoformat(), trigger)] = (label, conf)
            log.info("classification %s waits for its PestEvent (%s)", label, event_ts.isoformat())
            return False
        doc = serializable(await get_db()["pest_events"].find_one(filt))
        if doc is None:
            return False
        await hub.publish("pest_update", doc)
        event = PestEvent.model_validate(doc["event"])
        if is_pest_warning(event):
            await router._alert("pest", device_id, "warning", f"Pest detected: {event.yolo_pred}", doc)
        return True

    async def apply_unmatched(self, router: "MqttRouter", device_id: str, event: PestEvent) -> None:
        """Called after a PestEvent is stored: apply a classification that arrived first."""
        key = (device_id, event.ts.isoformat(), event.trigger_source)
        waiting = self.unmatched.pop(key, None)
        if waiting:
            await self._update_event(router, device_id, event.ts, event.trigger_source, waiting[0], waiting[1])


coordinator = PestCoordinator()
