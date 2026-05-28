"""Security-focused API tests."""

import os

import pytest

from app.config import get_settings


def test_health_is_public(client) -> None:
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] in ("healthy", "degraded")
    assert "registered_agents" in body or "database" in body


def test_agents_status_does_not_run_cycles(client) -> None:
    response = client.get("/agents/status")
    assert response.status_code == 200
    agents = response.json()["agents"]
    assert "marketing_agent" in agents
    assert agents["marketing_agent"]["status"] == "registered"


def test_ingest_requires_webhook_secret(client) -> None:
    response = client.post("/ingest/event", json={"event_type": "system_state", "payload": {}})
    assert response.status_code == 422  # missing header


def test_ingest_rejects_bad_webhook_secret(client) -> None:
    response = client.post(
        "/ingest/event",
        json={"event_type": "system_state", "payload": {}},
        headers={"X-Webhook-Secret": "wrong"},
    )
    assert response.status_code == 401


def test_marketing_cycle_requires_api_key_in_production(prod_client) -> None:
    response = prod_client.post("/marketing/cycle")
    assert response.status_code == 401


def test_marketing_cycle_with_api_key_in_production(prod_client) -> None:
    from unittest.mock import AsyncMock, patch

    from app.agents.marketing import MarketingAgent

    with patch.object(MarketingAgent, "run_cycle", new_callable=AsyncMock) as mock_run:
        mock_run.return_value = {"status": "ok", "items_generated": 0, "trends": 0}
        response = prod_client.post(
            "/marketing/cycle",
            headers={"X-API-Key": "prod-test-secret-key"},
        )
    assert response.status_code == 200


def test_metrics_requires_auth_in_production(prod_client) -> None:
    response = prod_client.get("/metrics")
    assert response.status_code == 401


def test_metrics_with_api_key_in_production(prod_client) -> None:
    response = prod_client.get("/metrics", headers={"X-API-Key": "prod-test-secret-key"})
    assert response.status_code == 200
    assert "text/plain" in response.headers.get("content-type", "")


def test_security_headers_present(client) -> None:
    response = client.get("/health")
    assert response.headers.get("X-Content-Type-Options") == "nosniff"
    assert response.headers.get("X-Frame-Options") == "DENY"


def test_production_docs_disabled(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.config import Settings

    prod = Settings(app_env="production")
    assert prod.is_production
    # Fresh app instance would set docs_url=None (see app.main FastAPI init)
    import importlib

    import app.main as main_mod

    monkeypatch.setenv("APP_ENV", "production")
    get_settings.cache_clear()
    importlib.reload(main_mod)
    assert main_mod.app.docs_url is None
    assert main_mod.app.openapi_url is None


def test_validate_production_secrets_detects_defaults() -> None:
    os.environ["APP_ENV"] = "production"
    os.environ["API_SECRET_KEY"] = "change-me"
    os.environ["EVENT_WEBHOOK_SECRET"] = ""
    get_settings.cache_clear()
    issues = get_settings().validate_production_secrets()
    assert any("API_SECRET_KEY" in i for i in issues)
    assert any("EVENT_WEBHOOK_SECRET" in i for i in issues)
