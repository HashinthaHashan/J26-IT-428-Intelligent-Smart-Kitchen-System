# KitchenGuard Phase 0 Architecture

KitchenGuard Phase 0 is the shared contract and backend spine for SLIIT project J26-IT-428. It validates MQTT messages from simulated devices, computes Phase 0 features, runs model-or-fallback inference, stores documents in MongoDB, republishes actuator commands, and exposes REST plus WebSocket APIs for the future app.

## MQTT Topic Map

Pattern: `kitchenguard/{component}/{device_id}/{channel}`

| Segment | Values | Direction | Notes |
| --- | --- | --- | --- |
| `component` | `lpg`, `pantry`, `pest`, `child` | both | Selects schema and handler. |
| `device_id` | short slug, for example `lpg01` | both | Must match payload `device_id`. |
| `telemetry` | channel | device to backend | Continuous readings, QoS 0. |
| `event` | channel | device/edge to backend | Discrete events and deterrence trials, QoS 1. |
| `cmd` | channel | backend to device | Actuator commands, QoS 1. |
| `status` | channel | device to backend | Retained online/offline status. Devices set Last Will when they connect. |

Backend subscriptions:

| Subscription | Purpose |
| --- | --- |
| `kitchenguard/+/+/telemetry` | LPG and pantry telemetry. |
| `kitchenguard/+/+/event` | Pest, deterrence, and child events. |
| `kitchenguard/+/+/status` | Device status updates. |

Examples:

| Topic | Schema |
| --- | --- |
| `kitchenguard/lpg/lpg01/telemetry` | `LpgTelemetry` |
| `kitchenguard/lpg/lpg01/cmd` | `ActuatorCommand` |
| `kitchenguard/pantry/pantry01/telemetry` | `PantryTelemetry`. One shared box = ONE device id; the sensor board publishes the same reading twice per cycle, once per `compartment` (`banana`, `potato`). |
| `kitchenguard/pantry/pantry01/camera` | PROPOSED (not stored by the backend yet): camera-board colour features per item. See `firmware/Pantry_Camera_Device/README.md`. |
| `kitchenguard/pest/pest-kitchen01/event` | `PestEvent` (trigger `PIR`, `IR`, `Vibration`) and `DeterrenceTrial` (species is null unless the camera answered while the trial was running). |
| `kitchenguard/pest/pest-kitchen01/capture_request` | Pest sensor board -> backend: `PestCaptureRequest` (`request_id`, `event_ts`, `trigger_source`, `zone`). |
| `kitchenguard/pest/pest-kitchen01/capture` | Backend -> camera board: the relayed capture order. |
| `kitchenguard/pest/pest-kitchen01/capture_done` | Camera board -> backend: `PestCaptureDone` (was the HTTP upload accepted). |
| `kitchenguard/pest/pest-kitchen01/cmd` | Backend -> sensor board: `ActuatorCommand`: `action: "classification"` (`source: auto`, `params: {species, confidence, request_id}`, attached to the running trial) or `action: "deterrent"` (`source: manual`, `params: {condition}`, a test). |
| `kitchenguard/pest/pest-kitchen01/camera_status` | Camera board retained online/offline + Last Will. |
| `kitchenguard/pest/pest-kitchen01/event` | `PestEvent` or `DeterrenceTrial` |
| `kitchenguard/child/child-cam01/event` | `ChildEvent` |

## Schema Reference

Schemas live in `shared_schemas/kitchenguard_schemas`. Both backend and simulators import this package. Every top-level message has `schema_version: int = 1`; every message timestamp is UTC field `ts: datetime`.

### `ActuatorCommand`

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | `int` | Contract version. |
| `device_id` | `str` | Target device. |
| `component` | `Literal["lpg","pantry","pest","child"]` | Component family. |
| `action` | `str` | Actuator name such as `fan`, `window`, `lock`. |
| `value` | `float` | `0/1` boolean or fractional command value. |
| `source` | `Literal["manual","auto","override"]` | Why the command was issued. |
| `issued_by` | `str | None` | User id for manual commands. |
| `ts` | `datetime` | UTC issue time. |

### `Alert`

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | `int` | Contract version. |
| `alert_id` | `str` | Unique alert id. |
| `component` | component literal | Source component. |
| `device_id` | `str` | Source device. |
| `severity` | `info`, `warning`, `danger`, `critical` | App severity. |
| `message` | `str` | Human-readable summary. |
| `data` | `dict` | Related event/telemetry payload. |
| `ts` | `datetime` | UTC creation time. |
| `acknowledged` | `bool` | Acknowledgement state. |

### `LpgTelemetry`

| Field | Type | Meaning |
| --- | --- | --- |
| `device_id` | `str` | LPG ESP32 slug. |
| `ts` | `datetime` | UTC sensor time. |
| `seq` | `int` | Device sequence number. |
| `ppm_raw` | `float` | MQ-2 ppm from edge calibration. |
| `temp_c` | `float` | DHT22 temperature. |
| `rh_pct` | `float` | DHT22 relative humidity. |
| `fan_on` | `bool` | Relay fan state. |
| `window_frac` | `float` | Servo window opening, `0.0-1.0`. |
| `edge_tier` | `Safe`, `Warning`, `Dangerous`, `Critical` | ESP32 edge decision. |
| `edge_offline_mode` | `bool` | Whether edge acted without cloud. |

### `LpgFeatures`

| Field | Type | Meaning |
| --- | --- | --- |
| `ppm_comp` | `float` | Compensated ppm. Currently raw ppm placeholder. |
| `d_ppm_5s` | `float` | 5 second ppm delta divided by 5. |
| `slope_30s` | `float` | 30 second ppm slope. |
| `ma10` | `float` | 10 sample moving average. |
| `ma30` | `float` | 30 sample moving average. |
| `d_rh_10s` | `float` | 10 second humidity delta divided by 10. |
| `tt700_s` | `float` | Estimated seconds to 700 ppm, clipped `0-3600`. |

### `LpgPrediction`

| Field | Type | Meaning |
| --- | --- | --- |
| `cloud_tier` | `Safe`, `Warning`, `Dangerous`, `Critical` | Backend tier. |
| `source` | `model`, `rule_fallback`, `safety_override` | Prediction source. |
| `confidence` | `float | None` | Model confidence when available. |

### `PantryTelemetry`

| Field | Type | Meaning |
| --- | --- | --- |
| `device_id` | `str` | Pantry ESP32 slug. |
| `compartment` | `banana`, `potato` | Compartment/item. |
| `ts` | `datetime` | UTC sensor time. |
| `mq3_ppm` | `float` | MQ-3 ppm. |
| `mq135_ppm` | `float` | MQ-135 ppm. |
| `temp_c` | `float` | Temperature. |
| `rh_pct` | `float` | Relative humidity. |
| `mass_kg` | `float | None` | Optional load cell mass. |
| `item_count` | `int | None` | Optional count. |
| `hue_mean` | `float | None` | Edge camera feature, never raw image. |
| `brown_pct` | `float | None` | Edge camera feature. |
| `green_pct` | `float | None` | Edge camera feature. |

### `PantryPrediction`

| Field | Type | Meaning |
| --- | --- | --- |
| `freshness_score` | `float` | `0-100` freshness. |
| `rsl_h` | `float` | Remaining shelf life in hours. |
| `stage` | `Fresh`, `Ripe`, `Deteriorating`, `Spoiled` | Pantry stage. |
| `source` | `model`, `rule_fallback` | Prediction source. |

### `PestEvent`

| Field | Type | Meaning |
| --- | --- | --- |
| `device_id` | `str` | Pest node id. |
| `ts` | `datetime` | UTC event time. |
| `zone` | zone literal | Kitchen zone. |
| `trigger_source` | `PIR`, `Vibration`, `Camera`, `None` | Trigger source. |
| `pir` | `bool` | PIR state. |
| `vib_rms_g` | `float` | Vibration RMS. |
| `vib_trigger` | `bool` | Vibration trigger state. |
| `ambient_lux` | `float` | Light level. |
| `camera_in_view` | `bool` | Whether camera saw the zone. |
| `yolo_pred` | pest class literal or `None` | Edge YOLO class. |
| `yolo_conf` | `float | None` | Edge YOLO confidence. |

### `DeterrenceTrial`

| Field | Type | Meaning |
| --- | --- | --- |
| `trial_id` | `str` | Trial identifier. |
| `device_id` | `str` | Pest node id. |
| `species` | `rat`, `cockroach` | Target species. |
| `condition` | `str` | Deterrence condition. |
| `zone` | zone literal | Kitchen zone. |
| `activation_s` | `int` | Actuator duration. |
| `observation_window_s` | `int` | Observation window. |
| `exited` | `bool | None` | Observed exit. |
| `time_to_leave_s` | `float | None` | Exit latency. |
| `system_verdict` | `left`, `remains`, `uncertain`, `None` | Automated verdict. |
| `manual_verdict` | `left`, `remains`, `None` | Human review result. |
| `ts` | `datetime` | UTC trial time. |

### `ChildEvent`

| Field | Type | Meaning |
| --- | --- | --- |
| `device_id` | `str` | Child safety edge box id. |
| `ts` | `datetime` | UTC event time. |
| `w` | `int` | Source frame width. |
| `h` | `int` | Source frame height. |
| `persons` | `list[BoxDet]` | Child/adult boxes only. |
| `hazards` | `list[BoxDet]` | Hazard boxes only. |
| `poses` | `list[list[list[float]]]` | `[person][17][x,y,conf]`, normalized. |

No raw images are transmitted or stored by this contract.

### `BoxDet`

| Field | Type | Meaning |
| --- | --- | --- |
| `cls` | `str` | Class name. |
| `conf` | `float` | Detector confidence. |
| `box` | `list[float]` | `[x0,y0,x1,y1]`, normalized `0-1`. |

### `ChildRiskPrediction`

| Field | Type | Meaning |
| --- | --- | --- |
| `risk_level` | `Safe`, `Warning`, `Danger` | Fused risk. |
| `danger_prob` | `float` | Placeholder probability. |
| `source` | `fusion_model`, `rule_fallback` | Prediction source. |

## Mongo Collections

| Collection | Shape |
| --- | --- |
| `devices` | `{device_id, component, last_seen, status, meta}` |
| `telemetry_lpg` | `{device_id, ts, raw: LpgTelemetry, features: LpgFeatures, prediction: LpgPrediction}` |
| `telemetry_pantry` | `{device_id, compartment, ts, raw: PantryTelemetry, features, prediction: PantryPrediction}` |
| `pest_events` | `{device_id, ts, event: PestEvent}` |
| `deterrence_trials` | `{trial_id, ...DeterrenceTrial fields}` |
| `child_events` | `{device_id, ts, event: ChildEvent, prediction: ChildRiskPrediction}` |
| `alerts` | `{alert_id, ...Alert fields}` |
| `actuator_log` | `{device_id, ...ActuatorCommand fields}` |
| `users` | Stub collection reserved for later auth. |

Indexes are created for `(device_id, ts)` and descending `ts` on telemetry/event-like collections. `devices.device_id` is unique.

## REST And WebSocket Contract

All REST endpoints except `/healthz` require `Authorization: Bearer <DEV_API_TOKEN>`. `/ws/live` is unauthenticated in Phase 0.

| Endpoint | Purpose |
| --- | --- |
| `GET /api/devices` | List devices with last seen and status. |
| `GET /api/lpg/{device_id}/latest` | Latest LPG raw/features/prediction. |
| `GET /api/lpg/{device_id}/history?minutes=60` | LPG history. |
| `POST /api/lpg/{device_id}/cmd` | Body `{action, value}`; publishes manual `ActuatorCommand`. |
| `GET /api/pantry/{device_id}/latest?compartment=banana` | Latest pantry prediction for compartment. |
| `GET /api/pantry/{device_id}/history?compartment=banana&minutes=1440` | Pantry readings of one compartment, newest first. |
| `POST /api/pest/{device_id}/photo` | Camera board upload: raw image body, headers `X-Request-Id`, `X-Image-Format` (`jpeg`/`rgb565`), `X-Image-Width/Height` (rgb565). Saves it, runs YOLO, updates the matching `PestEvent`, may send the species to the pest board (`classification` command). |
| `POST /api/pest/{device_id}/cmd` | Manual test: `{"condition": "control\|vibration_only\|led_only\|vibration_led"}` runs one deterrent trial. |
| `GET /api/pest/{device_id}/events?limit=50` | Pest events. |
| `POST /api/pest/{device_id}/trials/{trial_id}/review` | Body `{manual_verdict}`; stores human review. |
| `GET /api/child/{device_id}/latest` | Latest child safety event. |
| `GET /api/alerts?acknowledged=false` | Alert list. |
| `POST /api/alerts/{alert_id}/ack` | Acknowledge alert. |
| `WS /ws/live` | Pushes `{"type":"...","data":{...}}` for telemetry, events, commands, and alerts. |

## Inference Fallbacks

On startup, `app/services/inference.py` tries to load:

| Artifact | Fallback when missing or invalid |
| --- | --- |
| `ml/models/lpg_rf_backend.joblib` | `Safe < 150`, `Warning < 300`, `Dangerous < 700`, `Critical >= 700` using `ppm_comp`; hard 700 ppm override always returns `source="safety_override"`. |
| `ml/models/pantry_models_backend.joblib` | RULE PLACEHOLDER in `backend/app/services/pantry_rules.py` (not a model): per-sensor piecewise score using ethanol 81/108 ppm and ammonia 48/111 ppm (ripe/decomposed) anchors, worst sensor wins; `rsl_h = 168 h * score/100`; stages Fresh >= 75, Ripe >= 40, Deteriorating >= 15, else Spoiled; `source="rule_fallback"`. |

Pest species comes from `ml/models/pest_yolo.onnx` (ONNX YOLO, see `ml/models/README.md`); without the file, photos are saved but not classified, and trials simply have no species. Child fallback returns `Warning` if any hazard box overlaps any person box by IoU, otherwise `Safe`, with placeholder probability.

Missing model files log a clear warning once and never crash backend startup.

## Decisions

| Decision | Rationale |
| --- | --- |
| Shared schemas package | `shared_schemas/kitchenguard_schemas` is installable and imported by backend plus simulators, avoiding duplicated fields. |
| Auth stub | A single hardcoded dev bearer token from `.env` keeps Phase 0 simple and marks the JWT replacement point. |
| In-memory rolling buffers | LPG and pantry rolling features use process memory for speed in Phase 0. This resets on restart and should move to MongoDB or Redis before production. |
| Anonymous MQTT in dev | Mosquitto allows anonymous access only for local demos. TLS/auth belongs to production hardening outside Phase 0. |
| Child privacy | Child safety edge boxes send boxes/keypoints JSON only. Raw images are outside the schema and not accepted. |
