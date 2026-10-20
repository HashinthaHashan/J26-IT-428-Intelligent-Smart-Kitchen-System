from __future__ import annotations

import asyncio
import math

import aiomqtt
from kitchenguard_schemas import PantryTelemetry

from common import parser, publish_dict, publish_model, sleep_for, utcnow

# One physical pantry box holds both items: ONE device_id, two compartments (as the
# real sensor board publishes). The real board is also called "pantry01", so keep
# this simulator off while real hardware is connected.
DEVICE_ID = "pantry01"
ITEMS = {"banana": DEVICE_ID, "potato": DEVICE_ID}


async def run(host: str = "localhost", port: int = 1883, speed: float = 1.0) -> None:
    async with aiomqtt.Client(hostname=host, port=port, identifier="kg-pantry-sim") as client:
        await publish_dict(client, f"kitchenguard/pantry/{DEVICE_ID}/status", {"status": "online"}, qos=1)
        minute = 0
        while True:
            for item, device_id in ITEMS.items():
                age_h = minute / 60
                ripeness = min(age_h / (72 if item == "banana" else 240), 1.4)
                mq3 = 8 + ripeness * (80 if item == "banana" else 20) + math.sin(minute / 30)
                mq135 = 18 + ripeness * (45 if item == "banana" else 28)
                msg = PantryTelemetry(
                    device_id=device_id,
                    compartment=item,
                    ts=utcnow(),
                    mq3_ppm=mq3,
                    mq135_ppm=mq135,
                    temp_c=24 + math.sin(minute / 180) * 2,
                    rh_pct=68 + math.cos(minute / 160) * 4,
                    mass_kg=1.2 if item == "banana" else 2.0,
                    item_count=6 if item == "banana" else 8,
                    hue_mean=55 - ripeness * 22 if item == "banana" else 40,
                    brown_pct=min(90, ripeness * 60),
                    green_pct=max(0, 70 - ripeness * 60),
                )
                await publish_model(client, f"kitchenguard/pantry/{device_id}/telemetry", msg)
                print(f"[pantry] sent {item} minute={minute} mq3={mq3:.1f}")
            minute += 1
            await asyncio.sleep(sleep_for(60, speed))


if __name__ == "__main__":
    args = parser("KitchenGuard pantry simulator").parse_args()
    asyncio.run(run(args.host, args.port, args.speed))
