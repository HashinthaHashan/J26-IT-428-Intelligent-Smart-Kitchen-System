"""Prints MQTT messages as they arrive, to check what a device really publishes.

    python firmware/tools/watch_mqtt.py                       # everything under kitchenguard/
    python firmware/tools/watch_mqtt.py "kitchenguard/pantry/#"
    python firmware/tools/watch_mqtt.py "kitchenguard/pantry/pantry01/camera" --host 127.0.0.1

Needs the backend's Python packages (aiomqtt). Uses the broker on this laptop.
"""
import argparse
import asyncio
from datetime import datetime

import aiomqtt


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("topic", nargs="?", default="kitchenguard/#")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=1883)
    args = ap.parse_args()
    async with aiomqtt.Client(hostname=args.host, port=args.port, identifier="kg-watch") as client:
        await client.subscribe(args.topic)
        print(f"watching {args.topic} on {args.host}:{args.port}  (Ctrl+C to stop)\n")
        async for msg in client.messages:
            stamp = datetime.now().strftime("%H:%M:%S")
            print(f"{stamp}  {msg.topic}  {bytes(msg.payload).decode(errors='replace')}")


if __name__ == "__main__":
    # aiomqtt needs add_reader(), which Windows' default (proactor) loop lacks.
    try:
        with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
            runner.run(main())
    except KeyboardInterrupt:
        pass
