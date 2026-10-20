from __future__ import annotations

from datetime import datetime, timezone
from io import BytesIO

import numpy as np
import pytest
from PIL import Image

from kitchenguard_schemas import DeterrenceTrial, PestCaptureRequest, PestEvent

from app.core.config import get_settings
from app.db.mongo import get_db
from app.mqtt.router import router as mqtt_router
from app.services.pest_pipeline import coordinator, should_send_species
from app.services.pest_yolo import (
    PestClassification,
    PestDetector,
    decode_output,
    nms,
    normalise_label,
    set_detector,
)

DEVICE = "pest-kitchen01"
EVENT_TOPIC = f"kitchenguard/pest/{DEVICE}/event"
REQUEST_TOPIC = f"kitchenguard/pest/{DEVICE}/capture_request"


def _jpeg(size=(64, 48), color=(120, 90, 60)) -> bytes:
    out = BytesIO()
    Image.new("RGB", size, color).save(out, format="JPEG")
    return out.getvalue()


class FakePublisher:
    def __init__(self) -> None:
        self.sent: list[tuple[str, dict]] = []

    async def publish_json(self, topic, payload, qos=1):
        self.sent.append((topic, payload))


class FakeDetector:
    def __init__(self, label: str, conf: float | None) -> None:
        self.result = PestClassification(label, conf)

    def classify(self, _: bytes) -> PestClassification:
        return self.result


@pytest.fixture
def publisher(tmp_path, monkeypatch):
    monkeypatch.setenv("PEST_UPLOAD_DIR", str(tmp_path / "uploads"))
    get_settings.cache_clear()
    fake = FakePublisher()
    old = mqtt_router.publisher
    mqtt_router.set_publisher(fake)
    mqtt_router._last_alert.clear()  # the alert cooldown is per device and process-wide
    coordinator.pending.clear()
    coordinator.unmatched.clear()
    coordinator.configure(get_settings())
    yield fake
    mqtt_router.set_publisher(old)
    set_detector(None)
    get_settings.cache_clear()


def _event(trigger="PIR", ts=None) -> PestEvent:
    return PestEvent(
        device_id=DEVICE,
        ts=ts or datetime.now(timezone.utc).replace(microsecond=0),
        zone="Sink",
        trigger_source=trigger,
        pir=True,
        vib_rms_g=0.0,
        vib_trigger=False,
        ambient_lux=0.0,
        camera_in_view=False,
    )


async def _trigger(event: PestEvent, request_id: str, send_event: bool = True) -> None:
    """What Board 1 does: publish the event and a capture request for it."""
    request = PestCaptureRequest(
        device_id=DEVICE, request_id=request_id, ts=datetime.now(timezone.utc),
        event_ts=event.ts, trigger_source=event.trigger_source, zone=event.zone,
    )
    await mqtt_router.handle(REQUEST_TOPIC, request.model_dump_json().encode())
    if send_event:
        await mqtt_router.handle(EVENT_TOPIC, event.model_dump_json().encode())


async def _stored_event():
    return (await get_db()["pest_events"].find_one({"device_id": DEVICE}))["event"]


# ---------------------------------------------------------------- pure logic

def test_which_answers_are_sent_to_the_device():
    t = 0.6
    assert should_send_species(PestClassification("cockroach", 0.82), t)
    assert should_send_species(PestClassification("rat", 0.6), t)               # threshold is inclusive
    assert not should_send_species(PestClassification("rat", 0.59), t)          # a shaky guess is not written on a trial
    assert should_send_species(PestClassification("non_pest", 0.9), t)          # sent so the device can log it
    assert not should_send_species(PestClassification("none", None), t)         # nothing seen
    assert not should_send_species(None, t)                                     # no model loaded


def test_label_names_are_normalised():
    assert [normalise_label(n) for n in ("Rat", "cockroach", "Non-Pest", "non pest", "dog")] == [
        "rat", "cockroach", "non_pest", "non_pest", "unknown",
    ]


def _yolo_v8_output(n=8400, nc=3, rows=()):
    out = np.zeros((1, 4 + nc, n), dtype=np.float32)
    for i, (cx, cy, w, h, cls, conf) in enumerate(rows):
        out[0, :4, i] = (cx, cy, w, h)
        out[0, 4 + cls, i] = conf
    return out


def test_decode_yolov8_layout_and_nms():
    names = ["cockroach", "non_pest", "rat"]
    out = _yolo_v8_output(rows=[
        (320, 240, 100, 80, 0, 0.91),
        (322, 242, 100, 80, 0, 0.80),   # duplicate of the first: suppressed
        (100, 100, 40, 40, 2, 0.55),    # a different class elsewhere: kept
        (500, 400, 30, 30, 1, 0.10),    # below the confidence floor: dropped
    ])
    got = decode_output(out, names, min_conf=0.25)
    assert [(c, round(conf, 2)) for c, conf, _ in got] == [(0, 0.91), (2, 0.55)]
    # channels-last layout gives the same answer
    again = decode_output(out.transpose(0, 2, 1), names, min_conf=0.25)
    assert [(c, round(conf, 2)) for c, conf, _ in again] == [(0, 0.91), (2, 0.55)]
    x1, y1, x2, y2 = got[0][2]
    assert (x1, y1, x2, y2) == (270, 200, 370, 280)


def test_decode_objectness_and_end_to_end_layouts():
    names = ["cockroach", "non_pest", "rat"]
    v5 = np.zeros((1, 100, 5 + 3), dtype=np.float32)
    v5[0, 7, :5] = (200, 200, 50, 50, 0.9)  # box + objectness
    v5[0, 7, 5 + 2] = 0.8                   # class 'rat'
    assert [(c, round(conf, 2)) for c, conf, _ in decode_output(v5, names, 0.25)] == [(2, 0.72)]
    e2e = np.zeros((1, 10, 6), dtype=np.float32)
    e2e[0, 0] = (10, 20, 110, 120, 0.77, 1)  # x1,y1,x2,y2,conf,class
    assert [(c, round(conf, 2)) for c, conf, _ in decode_output(e2e, names, 0.25)] == [(1, 0.77)]
    with pytest.raises(ValueError, match="PEST_YOLO_CLASSES"):
        decode_output(np.zeros((1, 9, 50), dtype=np.float32), names, 0.25)


def test_nms_is_class_aware():
    boxes = np.array([[0, 0, 10, 10], [1, 1, 11, 11]], dtype=np.float32)
    scores = np.array([0.9, 0.8], dtype=np.float32)
    assert nms(boxes, scores, np.array([0, 0]), 0.45) == [0]        # same class: one survives
    assert sorted(nms(boxes, scores, np.array([0, 1]), 0.45)) == [0, 1]  # different classes both stay


def test_real_onnx_file_loads_and_classifies(tmp_path):
    """Exercises the real file path: onnxruntime, metadata class names, letterbox, decode."""
    torch = pytest.importorskip("torch")
    onnx = pytest.importorskip("onnx")
    pytest.importorskip("onnxruntime")

    out = torch.zeros(1, 7, 8400)
    out[0, :4, 100] = torch.tensor([320.0, 240.0, 100.0, 80.0])  # centre of the 640 letterbox
    out[0, 4 + 2, 100] = 0.88                                     # class index 2

    class Fake(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.register_buffer("out", out)

        def forward(self, x):
            return self.out + x.sum() * 0.0

    path = tmp_path / "pest_yolo.onnx"
    torch.onnx.export(Fake(), torch.zeros(1, 3, 640, 640), str(path), input_names=["images"],
                      output_names=["output0"], opset_version=17, dynamo=False)
    model = onnx.load(str(path))
    for key, value in {"names": "{0: 'cockroach', 1: 'non_pest', 2: 'rat'}", "imgsz": "[640, 640]"}.items():
        entry = model.metadata_props.add()
        entry.key, entry.value = key, value
    onnx.save(model, str(path))

    detector = PestDetector.load(tmp_path, "pest_yolo.onnx")
    assert detector is not None and detector.labels == ["cockroach", "non_pest", "rat"]
    result = detector.classify(_jpeg(size=(640, 480)))
    assert (result.label, round(result.conf, 2)) == ("rat", 0.88)
    x1, y1, x2, y2 = result.detections[0].box  # mapped back from the letterbox to the 640x480 photo
    assert (round(x1), round(y1), round(x2), round(y2)) == (270, 120, 370, 200)
    # a missing file is a warning, not a crash
    assert PestDetector.load(tmp_path, "nope.onnx") is None


def test_missing_model_file_is_not_fatal(tmp_path, caplog):
    assert PestDetector.load(tmp_path, "pest_yolo.onnx") is None
    assert "no code change needed" in caplog.text


# ------------------------------------------------------------ whole pipeline

async def test_capture_request_is_relayed_to_the_camera(publisher):
    event = _event()
    await _trigger(event, "pk-1")
    topic, payload = publisher.sent[0]
    assert topic == f"kitchenguard/pest/{DEVICE}/capture"
    assert payload["request_id"] == "pk-1" and payload["trigger_source"] == "PIR"
    assert "pk-1" in coordinator.pending


async def test_confident_cockroach_updates_the_event_and_is_sent_to_the_device(publisher, api_client):
    set_detector(FakeDetector("cockroach", 0.83))
    await _trigger(_event(), "pk-2")
    publisher.sent.clear()

    reply = await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg(), headers={"X-Request-Id": "pk-2"})
    body = reply.json()
    assert reply.status_code == 200
    assert (body["label"], body["confidence"], body["command"], body["event_updated"]) == ("cockroach", 0.83, "classification", True)

    stored = await _stored_event()
    assert (stored["yolo_pred"], stored["yolo_conf"], stored["camera_in_view"]) == ("cockroach", 0.83, True)
    assert stored["trigger_source"] == "PIR"  # the sensor that triggered it is unchanged

    # The answer goes to the device as a CLASSIFICATION: it is attached to the running trial and
    # decides nothing (there is no condition in it, and no timing window on the backend).
    topic, command = publisher.sent[-1]
    assert topic == f"kitchenguard/pest/{DEVICE}/cmd"
    assert (command["action"], command["source"]) == ("classification", "auto")
    assert command["params"] == {"species": "cockroach", "confidence": 0.83, "request_id": "pk-2"}

    # the events API now returns real species data, and a pest alert exists
    events = (await api_client.get(f"/api/pest/{DEVICE}/events")).json()
    assert events[0]["event"]["yolo_pred"] == "cockroach"
    alerts = (await api_client.get("/api/alerts")).json()
    assert any(a["component"] == "pest" and "cockroach" in a["message"] for a in alerts)
    assert body["saved_to"].endswith("pk-2.jpg")


async def test_a_slow_answer_is_still_recorded_because_nothing_waits_for_it(publisher, api_client):
    """The deterrent no longer waits, so there is no too-late: any answer updates the event and is sent."""
    set_detector(FakeDetector("rat", 0.9))
    await _trigger(_event(), "pk-5")
    coordinator.pending["pk-5"].received_mono -= 120  # as if the camera took two minutes
    publisher.sent.clear()
    body = (await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg(), headers={"X-Request-Id": "pk-5"})).json()
    assert body["command"] == "classification" and body["event_updated"] is True
    assert (await _stored_event())["yolo_pred"] == "rat"


async def test_non_pest_is_recorded_on_the_event_and_sent_for_logging_only(publisher, api_client):
    set_detector(FakeDetector("non_pest", 0.9))
    await _trigger(_event(), "pk-3")
    publisher.sent.clear()
    body = (await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg(), headers={"X-Request-Id": "pk-3"})).json()
    assert body["command"] == "classification"
    assert publisher.sent[-1][1]["params"]["species"] == "non_pest"
    assert "condition" not in publisher.sent[-1][1]["params"]  # it can no longer cancel or choose anything
    assert (await _stored_event())["yolo_pred"] == "non_pest"
    assert not any(a["component"] == "pest" for a in (await api_client.get("/api/alerts")).json())


async def test_low_confidence_is_recorded_on_the_event_but_not_sent_to_the_device(publisher, api_client):
    set_detector(FakeDetector("rat", 0.4))
    await _trigger(_event(), "pk-4")
    publisher.sent.clear()
    body = (await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg(), headers={"X-Request-Id": "pk-4"})).json()
    assert body["command"] == "none" and publisher.sent == []
    assert (await _stored_event())["yolo_pred"] == "rat"  # still recorded


async def test_photo_that_arrives_before_its_event_is_applied_when_the_event_arrives(publisher, api_client):
    set_detector(FakeDetector("cockroach", 0.9))
    event = _event()
    await _trigger(event, "pk-6", send_event=False)
    body = (await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg(), headers={"X-Request-Id": "pk-6"})).json()
    assert body["event_updated"] is False  # nothing to update yet
    await mqtt_router.handle(EVENT_TOPIC, event.model_dump_json().encode())
    assert (await _stored_event())["yolo_pred"] == "cockroach"


async def test_no_model_loaded_means_no_classification_but_the_photo_is_kept(publisher, api_client):
    set_detector(None)
    await _trigger(_event(), "pk-7")
    body = (await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg(), headers={"X-Request-Id": "pk-7"})).json()
    assert body["model_loaded"] is False and body["label"] is None and body["command"] == "none"
    assert (await _stored_event())["yolo_pred"] is None
    assert body["saved_to"]


async def test_manual_upload_without_a_request_is_classified_only(publisher, api_client):
    set_detector(FakeDetector("cockroach", 0.9))
    body = (await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg())).json()
    assert body["label"] == "cockroach" and body["matched_request"] is False and body["command"] == "none"


async def test_upload_validation_and_rgb565_conversion(publisher, api_client):
    set_detector(FakeDetector("none", None))
    assert (await api_client.post(f"/api/pest/{DEVICE}/photo", content=b"")).status_code == 400
    assert (await api_client.post(f"/api/pest/{DEVICE}/photo", content=b"not an image")).status_code == 400
    wrong = await api_client.post(f"/api/pest/{DEVICE}/photo", content=b"\x00" * 10,
                                  headers={"X-Image-Format": "rgb565", "X-Image-Width": "320", "X-Image-Height": "240"})
    assert wrong.status_code == 400  # size must be exactly 320*240*2
    raw = np.full((24, 32), (31 << 11) | (0 << 5) | 0, dtype=">u2").tobytes()  # pure red, big-endian
    ok = await api_client.post(f"/api/pest/{DEVICE}/photo", content=raw,
                               headers={"X-Image-Format": "rgb565", "X-Image-Width": "32", "X-Image-Height": "24"})
    assert ok.status_code == 200 and ok.json()["format_received"] == "rgb565"
    saved = Image.open(ok.json()["saved_to"]).convert("RGB")
    r, g, b = saved.getpixel((5, 5))
    assert r > 200 and g < 40 and b < 40
    assert (await api_client.post(f"/api/pest/{DEVICE}/photo", content=_jpeg(),
                                  headers={"Authorization": "Bearer wrong"})).status_code in {401, 403}


async def test_camera_upload_failure_ack_clears_the_wait(publisher):
    await _trigger(_event(), "pk-8")
    done = ('{"device_id":"%s","request_id":"pk-8","ts":"2026-10-09T12:00:00Z","upload_ok":false,'
            '"image_format":"jpeg","bytes":0,"detail":"HTTP 500"}' % DEVICE)
    await mqtt_router.handle(f"kitchenguard/pest/{DEVICE}/capture_done", done.encode())
    assert "pk-8" not in coordinator.pending


# --------------------------------------------------------- schemas and trials

async def test_ir_events_and_trials_with_or_without_species_are_accepted_and_listed(publisher, api_client):
    await mqtt_router.handle(EVENT_TOPIC, _event("IR").model_dump_json().encode())
    assert (await _stored_event())["trigger_source"] == "IR"

    base = dict(trial_id="t1", device_id=DEVICE, condition="vibration_led", zone="Sink",
                activation_s=15, observation_window_s=30, system_verdict="uncertain",
                ts=datetime.now(timezone.utc))
    unidentified = DeterrenceTrial(**base)  # the camera did not answer while the trial ran
    assert unidentified.species is None
    identified = DeterrenceTrial(**{**base, "trial_id": "t2", "species": "cockroach"})
    for trial in (unidentified, identified):
        await mqtt_router.handle(EVENT_TOPIC, trial.model_dump_json().encode())
    rows = (await api_client.get(f"/api/pest/{DEVICE}/trials")).json()
    assert sorted((d["trial_id"], d["species"]) for d in rows) == [("t1", None), ("t2", "cockroach")]
    # the old "informed" flag is gone from the contract
    assert not any("informed" in d for d in rows)
    with pytest.raises(Exception):
        DeterrenceTrial(**{**base, "informed": True})


async def test_manual_deterrent_command_endpoint(publisher, api_client):
    reply = await api_client.post(f"/api/pest/{DEVICE}/cmd", json={"condition": "led_only"})
    assert reply.status_code == 200
    topic, payload = publisher.sent[-1]
    assert topic == f"kitchenguard/pest/{DEVICE}/cmd"
    assert (payload["source"], payload["params"]) == ("manual", {"condition": "led_only"})
    assert (await api_client.post(f"/api/pest/{DEVICE}/cmd", json={"condition": "ultrasonic"})).status_code == 400
