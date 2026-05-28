"""Pytest fixtures."""

import os
from collections.abc import AsyncGenerator
from unittest.mock import AsyncMock, MagicMock

import pytest
from fastapi.testclient import TestClient

# Test defaults before app imports settings cache
os.environ.setdefault("APP_ENV", "development")
os.environ.setdefault("API_SECRET_KEY", "test-api-key")
os.environ.setdefault("EVENT_WEBHOOK_SECRET", "test-webhook-secret")
os.environ.setdefault("METRICS_REQUIRE_AUTH", "false")
os.environ.setdefault("RATE_LIMIT_PER_MINUTE", "10000")

from app.api.deps import get_db_session  # noqa: E402
from app.config import get_settings  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def _clear_settings_cache() -> None:
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def mock_db() -> AsyncMock:
    session = AsyncMock()
    session.commit = AsyncMock()
    session.rollback = AsyncMock()
    session.flush = AsyncMock()
    session.execute = AsyncMock()
    return session


@pytest.fixture
def client(mock_db: AsyncMock) -> TestClient:
    async def override_db() -> AsyncGenerator[AsyncMock, None]:
        yield mock_db

    app.dependency_overrides[get_db_session] = override_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def prod_client(mock_db: AsyncMock, monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("API_SECRET_KEY", "prod-test-secret-key")
    monkeypatch.setenv("EVENT_WEBHOOK_SECRET", "prod-webhook-secret")
    monkeypatch.setenv("METRICS_REQUIRE_AUTH", "true")
    get_settings.cache_clear()

    async def override_db() -> AsyncGenerator[AsyncMock, None]:
        yield mock_db

    app.dependency_overrides[get_db_session] = override_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    get_settings.cache_clear()
