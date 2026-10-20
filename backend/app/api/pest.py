from __future__ import annotations

import logging
from datetime import datetime, timezone
from io import BytesIO

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from pydantic import BaseModel

from kitchenguard_schemas import ActuatorCommand

from app.api.auth import require_dev_token
from app.core.config import get_settings
from app.db.mongo import get_db, serializable
from app.mqtt.router import router as mqtt_router
from app.services.pest_pipeline import coordinator

log = logging.getLogger(__name__)

MAX_JPEG_BYTES = 2_000_000
MAX_RAW_BYTES = 1_000_000  # an uncompressed QVGA RGB565 frame is 153,600 bytes
CONDITIONS = {"control", "vibration_only", "led_only", "vibration_led"}

router = APIRouter(prefix="/api/pest", tags=["pest"], dependencies=[Depends(require_dev_token)])


class ReviewIn(BaseModel):
    manual_verdict: str


@router.get("/{device_id}/events")
async def pest_events(device_id: str, limit: int = 50) -> list[dict]:
    rows = get_db()["pest_events"].find({"device_id": device_id}).sort("ts", -1).limit(limit)
    return [serializable(row) async for row in rows]


@router.post("/{device_id}/trials/{trial_id}/review")
async def review_trial(device_id: str, trial_id: str, body: ReviewIn) -> dict:
    result = await get_db()["deterrence_trials"].update_one(
        {"device_id": device_id, "trial_id": trial_id},
        {"$set": {"manual_verdict": body.manual_verdict}},
    )
    if result.modified_count == 0:
        raise HTTPException(404, "Deterrence trial not found")
    return {"device_id": device_id, "trial_id": trial_id, "manual_verdict": body.manual_verdict}


def _to_jpeg(body: bytes, image_format: str, width: int | None, height: int | None) -> bytes:
    """Validates the upload and returns JPEG bytes (RGB565 frames are converted)."""
    from PIL import Image, UnidentifiedImageError

    if image_format == "rgb565":
        if not width or not height:
            raise HTTPException(400, "rgb565 uploads need X-Image-Width and X-Image-Height")
        if len(body) > MAX_RAW_BYTES or len(body) != width * height * 2:
            raise HTTPException(400, f"rgb565 frame must be exactly width*height*2 = {width * height * 2} bytes (got {len(body)})")
        import numpy as np

        px = np.frombuffer(body, dtype=">u2").reshape(height, width)  # big-endian, as the camera sends it
        rgb = np.stack(
            [((px >> 11) & 0x1F) * 255 // 31, ((px >> 5) & 0x3F) * 255 // 63, (px & 0x1F) * 255 // 31], axis=-1
        ).astype("uint8")
        out = BytesIO()
        Image.fromarray(rgb, "RGB").save(out, format="JPEG", quality=92)
        return out.getvalue()
    if image_format != "jpeg":
        raise HTTPException(400, "X-Image-Format must be 'jpeg' or 'rgb565'")
    if len(body) > MAX_JPEG_BYTES:
        raise HTTPException(413, f"JPEG larger than {MAX_JPEG_BYTES} bytes")
    try:
        Image.open(BytesIO(body)).verify()
    except (UnidentifiedImageError, OSError) as exc:
        raise HTTPException(400, f"not a valid JPEG: {exc}") from exc
    return body


def _save_photo(device_id: str, request_id: str | None, jpeg: bytes) -> str:
    settings = get_settings()
    folder = settings.pest_upload_dir / device_id
    folder.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    safe_id = "".join(c for c in (request_id or "manual") if c.isalnum() or c in "-_")[:40] or "manual"
    path = folder / f"{stamp}_{safe_id}.jpg"
    path.write_bytes(jpeg)
    # Keep only the newest N photos so a long run cannot fill the disk.
    photos = sorted(folder.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
    for old in photos[settings.pest_keep_files :]:
        old.unlink(missing_ok=True)
    return str(path)


@router.post("/{device_id}/photo")
async def upload_photo(
    device_id: str,
    request: Request,
    x_request_id: str | None = Header(default=None),
    x_image_format: str = Header(default="jpeg"),
    x_image_width: int | None = Header(default=None),
    x_image_height: int | None = Header(default=None),
) -> dict:
    """Photo from the camera board: the raw image bytes are the request body.

    Headers: Authorization (Bearer), X-Request-Id (from the capture command),
    X-Image-Format (jpeg | rgb565), X-Image-Width / X-Image-Height (rgb565 only).
    The photo is saved, classified by YOLO and the matching PestEvent is updated.
    Without a known X-Request-Id (e.g. a manual curl test) it is still saved and
    classified, but no event is updated and no command is sent."""
    body = await request.body()
    if not body:
        raise HTTPException(400, "empty body")
    jpeg = _to_jpeg(body, x_image_format.lower(), x_image_width, x_image_height)
    saved = _save_photo(device_id, x_request_id, jpeg)
    result = await coordinator.handle_photo(mqtt_router, device_id, x_request_id, jpeg)
    log.info("photo %s saved to %s -> %s", x_request_id or "(manual)", saved, result)
    return {"saved_to": saved, "bytes": len(jpeg), "format_received": x_image_format.lower(), **result}


class DeterrentIn(BaseModel):
    condition: str


@router.post("/{device_id}/cmd")
async def pest_cmd(device_id: str, body: DeterrentIn, user_id: str = Depends(require_dev_token)) -> dict:
    """Manual test: make the device run one deterrent trial with this condition now."""
    if body.condition not in CONDITIONS:
        raise HTTPException(400, f"condition must be one of {sorted(CONDITIONS)}")
    command = ActuatorCommand(
        device_id=device_id,
        component="pest",
        action="deterrent",
        value=1.0,
        source="manual",
        issued_by=user_id,
        ts=datetime.now(timezone.utc),
        params={"condition": body.condition},
    )
    await mqtt_router.publish_command(command)
    return command.model_dump(mode="json")


@router.get("/{device_id}/trials")
async def pest_trials(device_id: str, limit: int = 50) -> list[dict]:
    """Deterrence trials, newest first: condition, species (if the camera answered while
    the trial was running), verdict and any manual review."""
    rows = get_db()["deterrence_trials"].find({"device_id": device_id}).sort("ts", -1).limit(min(max(limit, 1), 500))
    return [serializable(row) async for row in rows]
