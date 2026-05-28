"""WebSocket endpoint for real-time dashboard updates."""

import asyncio
import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.db.redis_client import (
    CHANNEL_ALERTS,
    CHANNEL_DASHBOARD,
    CHANNEL_SYSTEM_STATE,
    CHANNEL_TRADE_EVENTS,
    get_redis,
)

router = APIRouter(tags=["websocket"])


class ConnectionManager:
    def __init__(self) -> None:
        self.active: list[WebSocket] = []
        self._lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        async with self._lock:
            self.active.append(websocket)

    async def disconnect(self, websocket: WebSocket) -> None:
        async with self._lock:
            if websocket in self.active:
                self.active.remove(websocket)

    async def broadcast(self, message: dict) -> None:
        async with self._lock:
            clients = list(self.active)
        dead: list[WebSocket] = []
        for ws in clients:
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            await self.disconnect(ws)


manager = ConnectionManager()
_redis_listener_task: asyncio.Task | None = None
_redis_listener_lock = asyncio.Lock()


async def _redis_broadcast_loop() -> None:
    """Single shared Redis subscriber — avoids N duplicate listeners per WebSocket."""
    redis = await get_redis()
    pubsub = redis.pubsub()
    await pubsub.subscribe(
        CHANNEL_TRADE_EVENTS,
        CHANNEL_SYSTEM_STATE,
        CHANNEL_ALERTS,
        CHANNEL_DASHBOARD,
    )
    try:
        async for message in pubsub.listen():
            if message["type"] != "message":
                continue
            try:
                data = json.loads(message["data"])
            except json.JSONDecodeError:
                data = message["data"]
            await manager.broadcast({
                "channel": message["channel"],
                "data": data,
            })
    except asyncio.CancelledError:
        pass
    finally:
        await pubsub.unsubscribe()
        await pubsub.close()


async def _ensure_redis_listener() -> None:
    global _redis_listener_task
    async with _redis_listener_lock:
        if _redis_listener_task is None or _redis_listener_task.done():
            _redis_listener_task = asyncio.create_task(_redis_broadcast_loop())


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await _ensure_redis_listener()
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        pass
    finally:
        await manager.disconnect(websocket)
