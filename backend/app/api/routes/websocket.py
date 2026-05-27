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

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active.append(websocket)

    def disconnect(self, websocket: WebSocket) -> None:
        if websocket in self.active:
            self.active.remove(websocket)

    async def broadcast(self, message: dict) -> None:
        dead = []
        for ws in self.active:
            try:
                await ws.send_json(message)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)


manager = ConnectionManager()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket) -> None:
    await manager.connect(websocket)
    redis = await get_redis()
    pubsub = redis.pubsub()
    await pubsub.subscribe(
        CHANNEL_TRADE_EVENTS,
        CHANNEL_SYSTEM_STATE,
        CHANNEL_ALERTS,
        CHANNEL_DASHBOARD,
    )

    async def redis_listener() -> None:
        async for message in pubsub.listen():
            if message["type"] == "message":
                try:
                    data = json.loads(message["data"])
                    await manager.broadcast({
                        "channel": message["channel"],
                        "data": data,
                    })
                except json.JSONDecodeError:
                    await manager.broadcast({
                        "channel": message["channel"],
                        "data": message["data"],
                    })

    listener_task = asyncio.create_task(redis_listener())

    try:
        while True:
            data = await websocket.receive_text()
            if data == "ping":
                await websocket.send_json({"type": "pong"})
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    finally:
        listener_task.cancel()
        await pubsub.unsubscribe()
        await pubsub.close()
