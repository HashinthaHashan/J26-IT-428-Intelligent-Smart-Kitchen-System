from __future__ import annotations

import asyncio
import os
import sys
from pathlib import Path

import uvicorn
from amqtt.broker import Broker

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "simulators"))

# The preview stack runs from the repo, not Docker: look for model files and save
# camera photos in the repo (the settings default to the container paths /app/...).
os.environ.setdefault("ML_MODELS_DIR", str(ROOT / "ml" / "models"))
os.environ.setdefault("PEST_UPLOAD_DIR", str(ROOT / "uploads"))
os.environ.setdefault("USE_MEMORY_DB", "true")
os.environ.setdefault("START_MQTT", "true")
os.environ.setdefault("MQTT_HOST", "127.0.0.1")
# Ports default to the standard ones; PREVIEW_MQTT_PORT / PREVIEW_API_PORT let a second
# copy run beside yours (for example to test without stopping the real one).
MQTT_PORT = int(os.getenv("PREVIEW_MQTT_PORT", "1883"))
API_PORT = int(os.getenv("PREVIEW_API_PORT", "8000"))
os.environ["MQTT_PORT"] = str(MQTT_PORT)

from app.main import app  # noqa: E402
from child_sim import run as child_run  # noqa: E402
from lpg_sim import run as lpg_run  # noqa: E402
from pantry_sim import run as pantry_run  # noqa: E402
from pest_sim import run as pest_run  # noqa: E402


async def main() -> None:
    broker = Broker(
        {
            "listeners": {
                # Default 0.0.0.0 so real ESP32 devices on the LAN can connect. Set
                # MQTT_BIND=127.0.0.1 to keep the broker private to this laptop.
                "default": {
                    "type": "tcp",
                    "bind": f"{os.getenv('MQTT_BIND', '0.0.0.0')}:{MQTT_PORT}",
                },
            },
            "sys_interval": 10,
            "auth": {"allow-anonymous": True},
        }
    )
    await broker.start()
    bind_host = os.getenv("MQTT_BIND", "0.0.0.0")
    print(f"[preview] MQTT broker listening on {bind_host}:{MQTT_PORT}", flush=True)

    speed = float(os.getenv("PREVIEW_SPEED", "1"))
    server = uvicorn.Server(
        uvicorn.Config(
            app,
            # 0.0.0.0 so the ESP32-CAM can POST photos over the LAN (the phone app still
            # works through adb reverse). Set API_BIND=127.0.0.1 to keep it local.
            host=os.getenv("API_BIND", "0.0.0.0"),
            port=API_PORT,
            loop="none",
        )
    )
    # Simulators publish under the SAME device ids as the real hardware (lpg01,
    # pantry01), so a simulator must be OFF once its real device is connected.
    # PREVIEW_SIMULATORS is a comma list; default = only the ones with no hardware yet.
    # Example (everything simulated):  PREVIEW_SIMULATORS=lpg,pantry,pest,child
    available = {
        "lpg": lpg_run,
        "pantry": pantry_run,
        "pest": pest_run,
        "child": child_run,
    }
    wanted = [
        name.strip()
        for name in os.getenv("PREVIEW_SIMULATORS", "child").split(",")
        if name.strip()
    ]
    unknown = [name for name in wanted if name not in available]
    if unknown:
        raise SystemExit(f"PREVIEW_SIMULATORS has unknown name(s) {unknown}; use {sorted(available)}")
    simulators = [available[name]("127.0.0.1", MQTT_PORT, speed) for name in wanted]
    off = [name for name in available if name not in wanted]
    print(
        f"[preview] simulators ON: {', '.join(wanted) or 'none'}"
        + (f"; OFF (real hardware owns these ids): {', '.join(off)}" if off else ""),
        flush=True,
    )
    try:
        await asyncio.gather(server.serve(), *simulators)
    finally:
        await broker.shutdown()


if __name__ == "__main__":
    with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
        runner.run(main())
