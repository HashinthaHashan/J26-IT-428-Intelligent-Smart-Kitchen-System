from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "KitchenGuard API"
    dev_api_token: str = "dev-token"
    mongo_url: str = "mongodb://mongo:27017"
    mongo_db: str = "kitchenguard"
    mqtt_host: str = "mosquitto"
    mqtt_port: int = 1883
    mqtt_client_id: str = "kitchenguard-backend"
    ml_models_dir: Path = Path("/app/ml/models")
    start_mqtt: bool = True
    use_memory_db: bool = False

    # --- Pest pipeline (camera photo -> YOLO -> species recorded) ----------------
    # Minimum YOLO confidence for the species to be sent to the pest board (which
    # attaches it to its running trial). The PestEvent always gets the raw result.
    pest_conf_threshold: float = 0.6
    pest_upload_dir: Path = Path("uploads")
    pest_keep_files: int = 200  # newest uploaded photos kept per device
    pest_yolo_model: str = "pest_yolo.onnx"  # looked up inside ml_models_dir
    # Comma list overriding the class order when the ONNX file carries no names,
    # e.g. "cockroach,non_pest,rat".
    pest_yolo_classes: str = ""
    pest_yolo_min_conf: float = 0.25  # raw detections below this are discarded

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
