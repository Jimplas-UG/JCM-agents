"""Redis client for pub/sub, caching, and real-time state."""

from collections.abc import AsyncGenerator
from typing import Any

import redis.asyncio as aioredis

from app.config import get_settings

_redis: aioredis.Redis | None = None

CHANNEL_TRADE_EVENTS = "jcm:trade_events"
CHANNEL_SYSTEM_STATE = "jcm:system_state"
CHANNEL_ALERTS = "jcm:alerts"
CHANNEL_DASHBOARD = "jcm:dashboard"
CHANNEL_AGENT_BUS = "jcm:agent_bus"


async def get_redis() -> aioredis.Redis:
    global _redis
    if _redis is None:
        settings = get_settings()
        _redis = aioredis.from_url(
            settings.redis_url,
            encoding="utf-8",
            decode_responses=True,
        )
    return _redis


async def close_redis() -> None:
    global _redis
    if _redis is not None:
        await _redis.close()
        _redis = None


async def publish(channel: str, message: str) -> None:
    r = await get_redis()
    await r.publish(channel, message)


async def cache_set(key: str, value: str, ttl: int = 300) -> None:
    r = await get_redis()
    await r.setex(key, ttl, value)


async def cache_get(key: str) -> str | None:
    r = await get_redis()
    return await r.get(key)


async def redis_dependency() -> AsyncGenerator[aioredis.Redis, None]:
    yield await get_redis()
