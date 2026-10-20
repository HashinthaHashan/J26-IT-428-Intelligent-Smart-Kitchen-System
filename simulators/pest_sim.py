from __future__ import annotations

import asyncio
import random
import uuid

import aiomqtt
from kitchenguard_schemas import DeterrenceTrial, PestEvent

from common import parser, publish_dict, publish_model, sleep_for, utcnow

DEVICE_ID = "pest-kitchen01"
ZONES = ["Sink", "Pantry floor", "Trash bin", "Under cabinet", "Behind fridge"]


async def run(host: str = "localhost", port: int = 1883, speed: float = 1.0) -> None:
    async with aiomqtt.Client(hostname=host, port=port, identifier="kg-pest-sim") as client:
        await publish_dict(client, f"kitchenguard/pest/{DEVICE_ID}/status", {"status": "online"}, qos=1)
        while True:
            pred = random.choices(["rat", "cockroach", "non_pest", "none"], weights=[2, 4, 3, 6])[0]
            event = PestEvent(
                device_id=DEVICE_ID,
                ts=utcnow(),
                zone=random.choice(ZONES),
                trigger_source="Camera" if pred in {"rat", "cockroach"} else random.choice(["PIR", "Vibration", "None"]),
                pir=random.random() < 0.35,
                vib_rms_g=random.random() * 0.8,
                vib_trigger=random.random() < 0.25,
                ambient_lux=random.choice([2, 8, 40, 180]),
                camera_in_view=pred != "none",
                yolo_pred=pred if pred != "none" else "none",
                yolo_conf=random.uniform(0.62, 0.94) if pred in {"rat", "cockroach"} else random.uniform(0.2, 0.55),
            )
            await publish_model(client, f"kitchenguard/pest/{DEVICE_ID}/event", event, qos=1)
            print(f"[pest] sent {event.yolo_pred} conf={event.yolo_conf:.2f}")
            if pred in {"rat", "cockroach"} and random.random() < 0.25:
                trial = DeterrenceTrial(
                    trial_id=str(uuid.uuid4()),
                    device_id=DEVICE_ID,
                    species=pred,
                    condition=random.choice(["ultrasonic_only", "vibration_led", "control"]),
                    zone=event.zone,
                    activation_s=20,
                    observation_window_s=120,
                    exited=random.choice([True, False, None]),
                    time_to_leave_s=random.choice([18.0, 45.0, None]),
                    system_verdict=random.choice(["left", "remains", "uncertain"]),
                    ts=utcnow(),
                )
                await publish_model(client, f"kitchenguard/pest/{DEVICE_ID}/event", trial, qos=1)
                print(f"[pest] sent deterrence trial {trial.trial_id}")
            await asyncio.sleep(sleep_for(random.randint(20, 90), speed))


if __name__ == "__main__":
    args = parser("KitchenGuard pest simulator").parse_args()
    asyncio.run(run(args.host, args.port, args.speed))
