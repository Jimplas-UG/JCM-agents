"""FastAPI dependencies."""

from collections.abc import AsyncGenerator

from fastapi import Header, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.redis_client import get_redis
from app.db.session import AsyncSessionLocal


async def get_db_session() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise


async def verify_webhook_secret(
    x_webhook_secret: str = Header(..., alias="X-Webhook-Secret"),
) -> None:
    settings = get_settings()
    if settings.event_webhook_secret and x_webhook_secret != settings.event_webhook_secret:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid webhook secret",
        )
