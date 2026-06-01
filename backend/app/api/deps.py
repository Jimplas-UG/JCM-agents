"""FastAPI dependencies."""

import secrets
from collections.abc import AsyncGenerator

from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings

_mission_control_basic = HTTPBasic(auto_error=False)
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
    if not settings.event_webhook_secret:
        if settings.app_env == "production":
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Webhook secret not configured",
            )
        return
    if not secrets.compare_digest(x_webhook_secret, settings.event_webhook_secret):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid webhook secret",
        )


async def verify_api_key(
    x_api_key: str | None = Header(None, alias="X-API-Key"),
) -> None:
    """Require API key for mutating/admin routes when auth is enabled."""
    settings = get_settings()
    if not settings.api_auth_required:
        return
    if not x_api_key or not secrets.compare_digest(x_api_key, settings.api_secret_key):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key",
        )


async def verify_metrics_access(
    x_api_key: str | None = Header(None, alias="X-API-Key"),
) -> None:
    """Protect Prometheus scrape endpoint in production."""
    settings = get_settings()
    if not settings.metrics_auth_required:
        return
    if not x_api_key or not secrets.compare_digest(x_api_key, settings.api_secret_key):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Metrics endpoint requires valid X-API-Key",
        )


async def verify_mission_control_access(
    credentials: HTTPBasicCredentials | None = Depends(_mission_control_basic),
) -> None:
    """HTTP Basic Auth for CEO Copilot dashboard — owner access only."""
    settings = get_settings()
    if not settings.mission_control_auth_required:
        return
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="CEO Copilot requires authentication",
            headers={"WWW-Authenticate": 'Basic realm="JCM CEO Copilot"'},
        )
    user_ok = secrets.compare_digest(
        credentials.username.encode("utf-8"),
        settings.mission_control_user.encode("utf-8"),
    )
    pass_ok = secrets.compare_digest(
        credentials.password.encode("utf-8"),
        settings.mission_control_password.encode("utf-8"),
    )
    if not (user_ok and pass_ok):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid CEO Copilot credentials",
            headers={"WWW-Authenticate": 'Basic realm="JCM CEO Copilot"'},
        )


async def verify_mission_control_or_api_key(
    credentials: HTTPBasicCredentials | None = Depends(_mission_control_basic),
    x_api_key: str | None = Header(None, alias="X-API-Key"),
) -> None:
    """Mission Control data APIs — owner Basic Auth or ops X-API-Key."""
    settings = get_settings()
    if not settings.mission_control_auth_required:
        return
    if x_api_key and settings.api_secret_key and secrets.compare_digest(
        x_api_key, settings.api_secret_key
    ):
        return
    await verify_mission_control_access(credentials)
