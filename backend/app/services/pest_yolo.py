"""YOLO species detection for the pest camera photo.

Loads an exported Ultralytics-style ONNX model (``ml/models/pest_yolo.onnx``) with
the same "present-file check" pattern as the LPG and pantry models: if the file, or
onnxruntime, is missing, a clear warning is logged and the detector is simply absent
(``classify`` is then never called and the pipeline reports "no classification
available"). Nothing here raises at startup.

Supported ONNX output layouts (auto-detected):
  * YOLOv8 / YOLO11 raw:      [1, 4+nc, N]  or  [1, N, 4+nc]   (cx, cy, w, h, scores...)
  * YOLOv5-style with objectness: [1, N, 5+nc]
  * End-to-end / NMS exported:  [1, N, 6]  (x1, y1, x2, y2, conf, class)

Class names come from the model file's own metadata (Ultralytics writes ``names``),
or from the PEST_YOLO_CLASSES setting. They are normalised to the backend's
vocabulary: ``rat``, ``cockroach``, ``non_pest``.
"""

from __future__ import annotations

import ast
import logging
import time
from dataclasses import dataclass, field
from io import BytesIO
from pathlib import Path
from typing import Any

import numpy as np

log = logging.getLogger(__name__)

KNOWN_LABELS = {"rat", "cockroach", "non_pest"}


@dataclass
class Detection:
    label: str  # rat | cockroach | non_pest | unknown
    conf: float
    box: tuple[float, float, float, float]  # x1, y1, x2, y2 in ORIGINAL image pixels


@dataclass
class PestClassification:
    label: str  # rat | cockroach | non_pest | none (nothing detected)
    conf: float | None
    detections: list[Detection] = field(default_factory=list)
    inference_ms: float = 0.0  # total time in classify(): decode + preprocess + model + postprocess
    model_ms: float = 0.0  # just the onnxruntime run


def normalise_label(name: str) -> str:
    n = name.strip().lower().replace("-", "_").replace(" ", "_")
    if n in {"rat", "rats", "mouse", "rodent"}:
        return "rat"
    if n in {"cockroach", "cockroaches", "roach"}:
        return "cockroach"
    if n in {"non_pest", "nonpest", "not_pest", "no_pest", "background"}:
        return "non_pest"
    return "unknown"


def letterbox(image: Any, size: int) -> tuple[np.ndarray, float, tuple[float, float]]:
    """Resize keeping aspect ratio and pad to size x size (grey 114), like Ultralytics.

    Returns (CHW float32 in 0..1, scale, (pad_x, pad_y))."""
    from PIL import Image  # local import: Pillow is only needed once a model is loaded

    w, h = image.size
    scale = min(size / w, size / h)
    new_w, new_h = max(1, round(w * scale)), max(1, round(h * scale))
    resized = image.resize((new_w, new_h), Image.BILINEAR)
    canvas = Image.new("RGB", (size, size), (114, 114, 114))
    pad_x, pad_y = (size - new_w) / 2, (size - new_h) / 2
    canvas.paste(resized, (int(round(pad_x - 0.1)), int(round(pad_y - 0.1))))
    arr = np.asarray(canvas, dtype=np.float32) / 255.0
    return arr.transpose(2, 0, 1), scale, (pad_x, pad_y)


def _iou(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    x1 = np.maximum(a[0], b[:, 0])
    y1 = np.maximum(a[1], b[:, 1])
    x2 = np.minimum(a[2], b[:, 2])
    y2 = np.minimum(a[3], b[:, 3])
    inter = np.clip(x2 - x1, 0, None) * np.clip(y2 - y1, 0, None)
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[:, 2] - b[:, 0]) * (b[:, 3] - b[:, 1])
    return inter / np.maximum(area_a + area_b - inter, 1e-9)


def nms(boxes: np.ndarray, scores: np.ndarray, classes: np.ndarray, iou_threshold: float) -> list[int]:
    """Class-aware non-maximum suppression. Returns kept indices, best first."""
    keep: list[int] = []
    for cls in np.unique(classes):
        idx = np.where(classes == cls)[0]
        order = idx[np.argsort(-scores[idx])]
        while order.size:
            best = order[0]
            keep.append(int(best))
            if order.size == 1:
                break
            rest = order[1:]
            order = rest[_iou(boxes[best], boxes[rest]) < iou_threshold]
    return sorted(keep, key=lambda i: -scores[i])


def decode_output(
    output: np.ndarray,
    names: list[str],
    min_conf: float,
    iou_threshold: float = 0.45,
) -> list[tuple[int, float, np.ndarray]]:
    """Raw model output -> [(class_id, confidence, [x1,y1,x2,y2] in INPUT pixels)]."""
    arr = np.asarray(output)
    if arr.ndim == 3:
        arr = arr[0]
    if arr.ndim != 2:
        raise ValueError(f"unexpected YOLO output shape {np.asarray(output).shape}")
    nc = len(names)
    # Channels are the small dimension: [C, N] -> [N, C]
    if arr.shape[0] < arr.shape[1] and arr.shape[0] in {4 + nc, 5 + nc, 6}:
        arr = arr.T
    channels = arr.shape[1]

    if channels == 6 and 4 + nc != 6:  # end-to-end export: x1,y1,x2,y2,conf,cls
        mask = arr[:, 4] >= min_conf
        rows = arr[mask]
        return [(int(r[5]), float(r[4]), r[:4].astype(np.float32)) for r in rows]

    if channels == 4 + nc:
        scores_all = arr[:, 4:]
    elif channels == 5 + nc:
        scores_all = arr[:, 5:] * arr[:, 4:5]
    else:
        raise ValueError(
            f"model output has {channels} channels but {nc} classes {names} need {4 + nc} (or {5 + nc}). "
            "Set PEST_YOLO_CLASSES to the exact class list the model was trained with."
        )
    cls = scores_all.argmax(axis=1)
    conf = scores_all.max(axis=1)
    mask = conf >= min_conf
    if not mask.any():
        return []
    boxes_xywh, cls, conf = arr[mask, :4], cls[mask], conf[mask]
    boxes = np.empty_like(boxes_xywh, dtype=np.float32)
    boxes[:, 0] = boxes_xywh[:, 0] - boxes_xywh[:, 2] / 2
    boxes[:, 1] = boxes_xywh[:, 1] - boxes_xywh[:, 3] / 2
    boxes[:, 2] = boxes_xywh[:, 0] + boxes_xywh[:, 2] / 2
    boxes[:, 3] = boxes_xywh[:, 1] + boxes_xywh[:, 3] / 2
    kept = nms(boxes, conf, cls, iou_threshold)
    return [(int(cls[i]), float(conf[i]), boxes[i]) for i in kept]


class PestDetector:
    def __init__(self, session: Any, names: list[str], input_size: int, min_conf: float = 0.25) -> None:
        self.session = session
        self.names = names
        self.labels = [normalise_label(n) for n in names]
        self.input_size = input_size
        self.min_conf = min_conf
        self.input_name = session.get_inputs()[0].name

    # ---- loading ---------------------------------------------------------------

    @classmethod
    def load(cls, models_dir: Path, filename: str, classes_override: str = "", min_conf: float = 0.25):
        """Returns a detector, or None (with a logged warning) if it cannot be loaded."""
        path = Path(models_dir) / filename
        if not path.exists():
            log.warning(
                "Pest YOLO model %s is missing; photos are saved but no classification is available "
                "(drop the exported file there, no code change needed)",
                path,
            )
            return None
        try:
            import onnxruntime as ort
        except ImportError:
            log.warning("onnxruntime is not installed (pip install onnxruntime); pest classification disabled")
            return None
        try:
            session = ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])
            names = _names_from(session, classes_override)
            size = _input_size_from(session)
            detector = cls(session, names, size, min_conf)
        except Exception as exc:  # noqa: BLE001
            log.warning("Pest YOLO model %s failed to load (%s); pest classification disabled", path, exc)
            return None
        unknown = [n for n, label in zip(names, detector.labels) if label == "unknown"]
        if unknown:
            log.warning(
                "Pest YOLO classes %s do not map to rat/cockroach/non_pest and will be ignored", unknown
            )
        log.info("Pest YOLO model loaded: %s, classes=%s, input=%dpx", path.name, names, size)
        detector.warm_up()
        return detector

    def warm_up(self) -> None:
        """One throw-away run at startup: the first onnxruntime call is much slower than
        the rest, and that must not be paid by the first real photo (the species should arrive while the trial is still running)."""
        try:
            started = time.perf_counter()
            blank = np.full((1, 3, self.input_size, self.input_size), 0.45, dtype=np.float32)
            self.session.run(None, {self.input_name: blank})
            log.info("Pest YOLO warm-up run took %.0f ms (first-call cost, paid at startup)",
                     (time.perf_counter() - started) * 1000)
        except Exception as exc:  # noqa: BLE001
            log.warning("Pest YOLO warm-up failed (%s); the first photo may be slow", exc)

    # ---- inference -------------------------------------------------------------

    def classify(self, image_bytes: bytes) -> PestClassification:
        from PIL import Image

        started = time.perf_counter()
        image = Image.open(BytesIO(image_bytes)).convert("RGB")
        orig_w, orig_h = image.size
        tensor, scale, (pad_x, pad_y) = letterbox(image, self.input_size)
        run_started = time.perf_counter()
        output = self.session.run(None, {self.input_name: tensor[None, ...]})[0]
        model_ms = (time.perf_counter() - run_started) * 1000
        raw = decode_output(output, self.names, self.min_conf)

        detections: list[Detection] = []
        for class_id, conf, box in raw:
            if not 0 <= class_id < len(self.labels):
                continue
            x1 = float(np.clip((box[0] - pad_x) / scale, 0, orig_w))
            y1 = float(np.clip((box[1] - pad_y) / scale, 0, orig_h))
            x2 = float(np.clip((box[2] - pad_x) / scale, 0, orig_w))
            y2 = float(np.clip((box[3] - pad_y) / scale, 0, orig_h))
            detections.append(Detection(self.labels[class_id], conf, (x1, y1, x2, y2)))
        usable = [d for d in detections if d.label != "unknown"]
        if usable:
            best = max(usable, key=lambda d: d.conf)
            result = PestClassification(best.label, round(best.conf, 4), detections)
        else:
            result = PestClassification("none", None, detections)
        result.model_ms = model_ms
        result.inference_ms = (time.perf_counter() - started) * 1000
        log.info(
            "Pest inference: image %dx%d (%d bytes) -> %s%s in %.0f ms (model run %.0f ms, %d raw detection(s))",
            orig_w, orig_h, len(image_bytes), result.label,
            f" {result.conf:.2f}" if result.conf is not None else "",
            result.inference_ms, model_ms, len(detections),
        )
        return result


def _names_from(session: Any, override: str) -> list[str]:
    if override.strip():
        return [n.strip() for n in override.split(",") if n.strip()]
    meta = session.get_modelmeta().custom_metadata_map or {}
    if "names" in meta:
        parsed = ast.literal_eval(meta["names"])  # Ultralytics: "{0: 'rat', 1: 'cockroach', ...}"
        if isinstance(parsed, dict):
            return [str(parsed[k]) for k in sorted(parsed)]
        return [str(n) for n in parsed]
    raise ValueError(
        "the ONNX file has no 'names' metadata; set PEST_YOLO_CLASSES to the class order, e.g. "
        "'cockroach,non_pest,rat' (alphabetical is the Ultralytics default)"
    )


def _input_size_from(session: Any) -> int:
    shape = session.get_inputs()[0].shape  # [1, 3, H, W], dynamic dims are strings/None
    try:
        h, w = int(shape[2]), int(shape[3])
        return max(h, w)
    except (TypeError, ValueError, IndexError):
        meta = session.get_modelmeta().custom_metadata_map or {}
        if "imgsz" in meta:
            parsed = ast.literal_eval(meta["imgsz"])
            return int(parsed[0] if isinstance(parsed, (list, tuple)) else parsed)
        return 640


_detector: PestDetector | None = None


def init_detector(models_dir: Path, filename: str, classes_override: str = "", min_conf: float = 0.25):
    global _detector
    _detector = PestDetector.load(models_dir, filename, classes_override, min_conf)
    return _detector


def get_detector() -> PestDetector | None:
    return _detector


def set_detector(detector: PestDetector | None) -> None:
    """For tests."""
    global _detector
    _detector = detector
