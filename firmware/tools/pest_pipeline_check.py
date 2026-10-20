"""Plays BOTH pest boards against a running backend, to test the whole pipeline
before (or without) the real hardware.

    python firmware/tools/pest_pipeline_check.py                    # uses a generated photo
    python firmware/tools/pest_pipeline_check.py --photo cockroach.jpg
    python firmware/tools/pest_pipeline_check.py --mqtt-port 18830 --api-port 18000

What it does, with the exact message shapes the firmware sends:
  1. Board 1: publishes a PIR PestEvent and a capture_request.
  2. Backend: relays the request to the camera topic        (watch for it below).
  3. Camera: on that relay it uploads the photo over HTTP and publishes capture_done.
  4. Backend: runs YOLO, updates the event, and (if confident and in time) sends the
     species to Board 1's cmd topic as a 'classification' command   (watch for it below).
  5. Board 1 (as the firmware does) attaches a rat/cockroach answer to its running trial and
     publishes the trial at the end; here the trial is published straight away.
  6. It prints the stored event (yolo_pred / yolo_conf) AND the stored trial (species), so
     you can see the species on both.

Stop the real boards first (or use a different --device) so they do not also answer.
Needs the backend's Python packages (aiomqtt, httpx, Pillow).
"""
import argparse
import asyncio
import json
import time
from datetime import datetime, timezone
from io import BytesIO

import aiomqtt
import httpx
from PIL import Image, ImageDraw


def make_photo() -> bytes:
    image = Image.new("RGB", (640, 480), (200, 200, 195))
    ImageDraw.Draw(image).ellipse((260, 190, 380, 290), fill=(70, 40, 20))  # a dark blob on a pale floor
    out = BytesIO()
    image.save(out, format="JPEG", quality=85)
    return out.getvalue()


async def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--mqtt-port", type=int, default=1883)
    ap.add_argument("--api-port", type=int, default=8000)
    ap.add_argument("--token", default="dev-token")
    ap.add_argument("--device", default="pest-kitchen01")
    ap.add_argument("--zone", default="Sink")
    ap.add_argument("--trigger", default="PIR", choices=["PIR", "Vibration"])
    ap.add_argument("--photo", help="JPEG to upload (default: a generated one)")
    args = ap.parse_args()

    photo = open(args.photo, "rb").read() if args.photo else make_photo()
    base = f"kitchenguard/pest/{args.device}"
    api = f"http://{args.host}:{args.api_port}"
    now = datetime.now(timezone.utc).replace(microsecond=0)
    request_id = f"check-{int(time.time()) % 100000}"
    iso = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    t0 = time.monotonic()
    seen: dict[str, str] = {}

    async with aiomqtt.Client(hostname=args.host, port=args.mqtt_port, identifier="kg-pest-check") as client:
        await client.subscribe(f"{base}/capture")
        await client.subscribe(f"{base}/cmd")

        # --- Board 1: the event, then the capture request (as pest sensor firmware does) ---
        event = {
            "schema_version": 1, "device_id": args.device, "ts": iso, "zone": args.zone,
            "trigger_source": args.trigger, "pir": args.trigger == "PIR", "vib_rms_g": 0.0,
            "vib_trigger": args.trigger == "Vibration", "ambient_lux": 0.0, "camera_in_view": False,
            "yolo_pred": None, "yolo_conf": None,
        }
        request = {
            "schema_version": 1, "device_id": args.device, "request_id": request_id,
            "ts": iso, "event_ts": iso, "trigger_source": args.trigger, "zone": args.zone,
        }
        await client.publish(f"{base}/event", json.dumps(event))
        await client.publish(f"{base}/capture_request", json.dumps(request))
        print(f"[board 1] published PestEvent + capture_request {request_id} ({args.trigger}, {args.zone})")

        async def camera(order: dict) -> None:
            print(f"[camera ] +{time.monotonic() - t0:5.2f}s capture order received, uploading {len(photo)} bytes")
            async with httpx.AsyncClient(timeout=10) as http:
                reply = await http.post(
                    f"{api}/api/pest/{args.device}/photo", content=photo,
                    headers={"Authorization": f"Bearer {args.token}", "X-Request-Id": order["request_id"],
                             "X-Image-Format": "jpeg", "Content-Type": "image/jpeg"},
                )
            print(f"[camera ] +{time.monotonic() - t0:5.2f}s HTTP {reply.status_code}: {reply.text[:300]}")
            done = {"schema_version": 1, "device_id": args.device, "request_id": order["request_id"],
                    "ts": iso, "upload_ok": reply.status_code == 200, "image_format": "jpeg", "bytes": len(photo)}
            await client.publish(f"{base}/capture_done", json.dumps(done))

        deadline = time.monotonic() + 12
        tasks = []
        while time.monotonic() < deadline and ("capture" not in seen or "cmd" not in seen):
            try:
                message = await asyncio.wait_for(client.messages.__anext__(), timeout=1.0)
            except asyncio.TimeoutError:
                if "capture" in seen and time.monotonic() - t0 > 6:
                    break  # the camera answered but no species came (no model, or low confidence)
                continue
            topic, payload = str(message.topic), json.loads(bytes(message.payload))
            if topic.endswith("/capture"):
                seen["capture"] = topic
                tasks.append(asyncio.create_task(camera(payload)))
            elif topic.endswith("/cmd"):
                seen["cmd"] = topic
                seen["params"] = payload.get("params") or {}
                print(f"[board 1] +{time.monotonic() - t0:5.2f}s {payload.get('action').upper()} received: "
                      f"{json.dumps(payload.get('params'))} (source={payload.get('source')})")
        for task in tasks:
            await task

    # --- Board 1: attach a rat/cockroach answer to the running trial, publish the trial ---
    params = seen.get("params", {})
    species = params.get("species") if params.get("species") in ("rat", "cockroach") else None
    async with aiomqtt.Client(hostname=args.host, port=args.mqtt_port, identifier="kg-pest-check-b1") as client:
        trial = {
            "schema_version": 1, "trial_id": f"{args.device}-CHK-{request_id}", "device_id": args.device,
            "species": species, "condition": "vibration_led", "zone": args.zone, "activation_s": 15,
            "observation_window_s": 30, "exited": None, "time_to_leave_s": None,
            "system_verdict": "uncertain", "ts": iso,
        }
        await client.publish(f"{base}/event", json.dumps(trial))
        print(f"[board 1] trial published with species={species} (null if the camera said non-pest or never answered)")
    await asyncio.sleep(0.5)

    if "capture" not in seen:
        print("!! the camera topic never received the relayed capture order: is the backend running and subscribed?")
    if "cmd" not in seen:
        print("[board 1] no command arrived: the trial would run without a species (no model loaded or low confidence)")

    async with httpx.AsyncClient(timeout=10) as http:
        events = (await http.get(f"{api}/api/pest/{args.device}/events", headers={"Authorization": f"Bearer {args.token}"})).json()
    mine = [e for e in events if e["ts"].startswith(iso[:19])]
    if mine:
        ev = mine[0]["event"]
        print(f"[backend] stored event: trigger={ev['trigger_source']} yolo_pred={ev['yolo_pred']} "
              f"yolo_conf={ev['yolo_conf']} camera_in_view={ev['camera_in_view']}")
    else:
        print("[backend] the event was not found in /events")
    async with httpx.AsyncClient(timeout=10) as http:
        trials = (await http.get(f"{api}/api/pest/{args.device}/trials", headers={"Authorization": f"Bearer {args.token}"})).json()
    mine_t = [t for t in trials if t["trial_id"].endswith(request_id)]
    if mine_t:
        print(f"[backend] stored trial: condition={mine_t[0]['condition']} species={mine_t[0]['species']} "
              f"verdict={mine_t[0]['system_verdict']}")
    else:
        print("[backend] the trial was not found in /trials")


if __name__ == "__main__":
    # aiomqtt needs add_reader(), which Windows' default (proactor) loop lacks.
    try:
        with asyncio.Runner(loop_factory=asyncio.SelectorEventLoop) as runner:
            runner.run(main())
    except KeyboardInterrupt:
        pass
