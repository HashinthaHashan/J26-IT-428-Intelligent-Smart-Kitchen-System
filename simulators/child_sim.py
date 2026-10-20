from __future__ import annotations

import asyncio

import aiomqtt
from kitchenguard_schemas import BoxDet, ChildEvent

from common import parser, pose_stub, publish_dict, publish_model, sleep_for, utcnow

DEVICE_ID = "child-cam01"


async def run(host: str = "localhost", port: int = 1883, speed: float = 1.0) -> None:
    async with aiomqtt.Client(hostname=host, port=port, identifier="kg-child-sim") as client:
        await publish_dict(client, f"kitchenguard/child/{DEVICE_ID}/status", {"status": "online"}, qos=1)
        seq = 0
        while True:
            phase = seq % 45
            person_x = 0.1 + min(phase, 30) * 0.015
            person = BoxDet(cls="child", conf=0.91, box=[person_x, 0.35, person_x + 0.18, 0.85])
            hazards = [BoxDet(cls="knife", conf=0.88, box=[0.58, 0.42, 0.72, 0.55])]
            if phase > 32:
                hazards.append(BoxDet(cls="gas_stove", conf=0.83, box=[0.48, 0.36, 0.66, 0.62]))
            event = ChildEvent(
                device_id=DEVICE_ID,
                ts=utcnow(),
                w=1280,
                h=720,
                persons=[person],
                hazards=hazards,
                poses=[pose_stub(person_x + 0.06, 0.42)],
            )
            await publish_model(client, f"kitchenguard/child/{DEVICE_ID}/event", event, qos=1)
            print(f"[child] sent seq={seq} persons={len(event.persons)} hazards={len(event.hazards)}")
            seq += 1
            await asyncio.sleep(sleep_for(5, speed))


if __name__ == "__main__":
    args = parser("KitchenGuard child simulator").parse_args()
    asyncio.run(run(args.host, args.port, args.speed))
