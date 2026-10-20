from __future__ import annotations

import asyncio
import contextlib
import math

from kitchenguard_schemas import ActuatorCommand, LpgTelemetry

from common import parser, publish_dict, publish_model, sleep_for, utcnow
import aiomqtt

DEVICE_ID = "lpg01"
TOPIC = f"kitchenguard/lpg/{DEVICE_ID}/telemetry"
CMD_TOPIC = f"kitchenguard/lpg/{DEVICE_ID}/cmd"
STATUS_TOPIC = f"kitchenguard/lpg/{DEVICE_ID}/status"


def tier(ppm: float) -> str:
    return "Safe" if ppm < 150 else "Warning" if ppm < 300 else "Dangerous" if ppm < 700 else "Critical"


async def listen_cmd(client: aiomqtt.Client, state: dict[str, float | bool]) -> None:
    await client.subscribe(CMD_TOPIC, qos=1)
    async for msg in client.messages:
        cmd = ActuatorCommand.model_validate_json(bytes(msg.payload))
        if cmd.action == "fan":
            state["fan_on"] = bool(cmd.value)
        if cmd.action == "window":
            state["window_frac"] = max(0.0, min(1.0, cmd.value))
        print(f"[lpg] received command {cmd.action}={cmd.value}")


async def run(host: str = "localhost", port: int = 1883, speed: float = 1.0) -> None:
    state: dict[str, float | bool] = {"fan_on": False, "window_frac": 0.0}
    async with aiomqtt.Client(hostname=host, port=port, identifier="kg-lpg-sim") as client:
        await publish_dict(client, STATUS_TOPIC, {"status": "online"}, qos=1)
        listener = asyncio.create_task(listen_cmd(client, state))
        seq = 0
        try:
            while True:
                phase = (seq // 90) % 4
                x = seq % 90
                if phase == 0:
                    ppm = 60 + 10 * math.sin(x / 8)
                elif phase == 1:
                    ppm = 90 + 220 * math.exp(-((x - 20) ** 2) / 160)
                elif phase == 2:
                    ppm = 120 + x * 5.5
                else:
                    ppm = min(900, 250 + x * 14)
                edge = tier(ppm)
                if edge in {"Dangerous", "Critical"}:
                    state["fan_on"] = True
                    state["window_frac"] = 1.0
                msg = LpgTelemetry(
                    device_id=DEVICE_ID,
                    ts=utcnow(),
                    seq=seq,
                    ppm_raw=ppm,
                    temp_c=29 + math.sin(seq / 20),
                    rh_pct=70 + math.sin(seq / 15) * 3,
                    fan_on=bool(state["fan_on"]),
                    window_frac=float(state["window_frac"]),
                    edge_tier=edge,
                    edge_offline_mode=False,
                )
                await publish_model(client, TOPIC, msg)
                print(f"[lpg] sent seq={seq} ppm={ppm:.1f} tier={edge}")
                seq += 1
                await asyncio.sleep(sleep_for(1, speed))
        finally:
            listener.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await listener


if __name__ == "__main__":
    args = parser("KitchenGuard LPG simulator").parse_args()
    asyncio.run(run(args.host, args.port, args.speed))
