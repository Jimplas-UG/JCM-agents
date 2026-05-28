"""Ingest boundary validation tests."""

from app.config import get_settings


def test_batch_size_limit_configured() -> None:
    assert get_settings().event_ingestion_batch_size == 100


def test_batch_rejects_oversized_payload(client) -> None:
    settings = get_settings()
    limit = settings.event_ingestion_batch_size
    events = [{"event_type": "system_state", "payload": {}} for _ in range(limit + 1)]
    response = client.post(
        "/ingest/batch",
        json={"events": events},
        headers={"X-Webhook-Secret": settings.event_webhook_secret},
    )
    assert response.status_code == 413
