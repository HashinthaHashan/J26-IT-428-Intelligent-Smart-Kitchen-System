from __future__ import annotations

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.encoders import jsonable_encoder

router = APIRouter()


class LiveHub:
    def __init__(self) -> None:
        self._clients: set[WebSocket] = set()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self._clients.add(websocket)

    def disconnect(self, websocket: WebSocket) -> None:
        self._clients.discard(websocket)

    async def publish(self, msg_type: str, data: dict) -> None:
        stale: list[WebSocket] = []
        frame = jsonable_encoder({"type": msg_type, "data": data})
        for websocket in list(self._clients):
            try:
                await websocket.send_json(frame)
            except RuntimeError:
                stale.append(websocket)
        for websocket in stale:
            self.disconnect(websocket)


hub = LiveHub()


@router.websocket("/ws/live")
async def live_ws(websocket: WebSocket) -> None:
    await hub.connect(websocket)
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        hub.disconnect(websocket)
