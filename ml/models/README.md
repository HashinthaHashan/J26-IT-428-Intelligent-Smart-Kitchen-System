# Model Artifacts

Drop trained backend artifacts here (the backend logs one warning per missing file and
uses documented fallbacks, so none of them is required to start):

| File | Used for | When missing |
| --- | --- | --- |
| `lpg_rf_backend.joblib` | LPG cloud tier | rule fallback (150/300/700 ppm) |
| `pantry_models_backend.joblib` | pantry freshness | rule placeholder in `backend/app/services/pantry_rules.py` |
| `pest_yolo.onnx` | species detection on the pest camera photo | photos are saved, no classification, trials have no species |

When you run `python backend/preview_stack.py` this folder is the repo's `ml/models/`
(the stack sets `ML_MODELS_DIR` for you). In Docker it is `/app/ml/models`.

## Pest YOLO model: exporting and dropping it in

Export from your Colab notebook (Ultralytics YOLOv8 / YOLO11) and copy the result here as
`pest_yolo.onnx`:

```python
from ultralytics import YOLO
YOLO("runs/detect/train/weights/best.pt").export(format="onnx", imgsz=640, opset=12, simplify=True)
```

Then restart the backend. The startup log must say
`Pest YOLO model loaded: pest_yolo.onnx, classes=[...], input=640px`. No code change is needed.

**Verified with the project's own `best.pt`** (YOLOv8n, 3 classes, exported with
`opset=12, imgsz=640, simplify=False`, output `[1, 7, 8400]`): the backend log shows
`Pest YOLO model loaded: pest_yolo.onnx, classes=['rat', 'cockroach', 'non_pest'], input=640px`.
Note the class order is `rat, cockroach, non_pest` (not alphabetical); it is read from the
file, so nothing needs configuring. Measured on the development laptop (Intel i5-1035G1,
CPU only, onnxruntime): warm-up 120 to 140 ms at startup, then median 122 ms, p95 142 ms, worst
305 ms per 640x480 JPEG. Every inference logs one line:
`Pest inference: image 640x480 (47193 bytes) -> non_pest 0.61 in 123 ms (model run 111 ms, ...)`.

Things that matter:

* **Class order and names.** An Ultralytics export stores them inside the file (`names`
  metadata) and the backend reads them from there. The names are normalised to the
  backend's words: `rat`, `cockroach`, `non_pest` (so `Non-Pest` and `non pest` also work).
  A class with any other name is ignored (a warning is logged). If your file has no `names`
  metadata, set `PEST_YOLO_CLASSES` to the training order, e.g. `cockroach,non_pest,rat`
  (alphabetical is the Ultralytics default). **A wrong order silently swaps species**, so
  check the log line above against your notebook's `model.names`.
* **Input size.** Read from the file (`imgsz`); photos are letterboxed to it, so any camera
  size works. 640 matches the camera board's VGA frame.
* **Output layout.** The standard raw export (`[1, 4+classes, N]`) is expected. The
  `[1, N, 4+classes]`, `[1, N, 5+classes]` (objectness) and NMS-embedded `[1, N, 6]` layouts are
  also detected automatically. Anything else fails loudly at the first photo with a message
  naming the number of channels it saw.
* **Thresholds** (environment variables or `.env`):
  `PEST_YOLO_MIN_CONF` (0.25) drops weak raw detections; `PEST_CONF_THRESHOLD` (0.6) is the
  confidence needed for the species to be SENT to the pest board, which attaches rat/cockroach to
  its running trial. The deterrent never waits for or depends on this answer. The `PestEvent`
  always stores the raw result whatever the confidence.
* Needs `onnxruntime` (in `backend/requirements.txt`).

Until your file is here, the whole pipeline can still be exercised with
`python firmware/tools/pest_pipeline_check.py`, and a photo can be classified manually (see
`firmware/Pest_Sensor_Device/README.md`).
