from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api import alerts, child, devices, lpg, pantry, pest, ws
from app.core.config import get_settings
from app.core.logging import configure_logging
from app.db.mongo import close, connect
from app.mqtt.client import MqttService
from app.mqtt.router import router as mqtt_router
from app.services.inference import init_registry
from app.services.pest_pipeline import coordinator as pest_coordinator
from app.services.pest_yolo import init_detector


@asynccontextmanager
async def lifespan(app: FastAPI):
    configure_logging()
    settings = get_settings()
    await connect(settings)
    init_registry(settings.ml_models_dir)
    init_detector(
        settings.ml_models_dir,
        settings.pest_yolo_model,
        settings.pest_yolo_classes,
        settings.pest_yolo_min_conf,
    )
    pest_coordinator.configure(settings)
    mqtt_service: MqttService | None = None
    if settings.start_mqtt:
        mqtt_service = MqttService(settings, mqtt_router.handle)
        mqtt_router.set_publisher(mqtt_service)
        await mqtt_service.start()
    app.state.mqtt = mqtt_service
    yield
    if mqtt_service:
        await mqtt_service.stop()
    await close()


app = FastAPI(title="KitchenGuard Phase 0", lifespan=lifespan)
app.include_router(devices.router)
app.include_router(lpg.router)
app.include_router(pantry.router)
app.include_router(pest.router)
app.include_router(child.router)
app.include_router(alerts.router)
app.include_router(ws.router)


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}
