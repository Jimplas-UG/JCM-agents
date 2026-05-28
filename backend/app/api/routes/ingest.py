"""Event ingestion endpoints — receive BSv3.2 events from execution layer."""

from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, verify_webhook_secret
from app.config import get_settings
from app.metrics.prometheus import FILTER_BLOCKS_TOTAL, TRADE_EVENTS_TOTAL
from app.services.event_pipeline import EventPipeline

router = APIRouter(prefix="/ingest", tags=["ingestion"])


@router.post("/event", dependencies=[Depends(verify_webhook_secret)])
async def ingest_event(
    body: dict[str, Any],
    db: AsyncSession = Depends(get_db_session),
) -> dict[str, Any]:
    event_type = body.get("event_type", "unknown")
    payload = body.get("payload", body)

    pipeline = EventPipeline(db)
    try:
        result = await pipeline.ingest(event_type, payload)
    except ValidationError as exc:
        raise HTTPException(status_code=422, detail=exc.errors()) from exc

    symbol = payload.get("symbol", "unknown") if isinstance(payload, dict) else "unknown"
    if event_type in ("trade_executed", "trade_closed"):
        TRADE_EVENTS_TOTAL.labels(event_type=event_type, symbol=symbol).inc()
    elif event_type == "trade_blocked":
        for f in payload.get("blocked_by", []) if isinstance(payload, dict) else []:
            FILTER_BLOCKS_TOTAL.labels(filter=f).inc()

    return result


@router.post("/batch", dependencies=[Depends(verify_webhook_secret)])
async def ingest_batch(
    body: dict[str, Any],
    db: AsyncSession = Depends(get_db_session),
) -> dict[str, Any]:
    settings = get_settings()
    events = body.get("events", [])
    if len(events) > settings.event_ingestion_batch_size:
        raise HTTPException(
            status_code=413,
            detail=f"Batch exceeds max size of {settings.event_ingestion_batch_size}",
        )

    pipeline = EventPipeline(db)
    results = []
    errors = []
    for i, event in enumerate(events):
        event_type = event.get("event_type", "unknown")
        payload = event.get("payload", event)
        try:
            result = await pipeline.ingest(event_type, payload)
            results.append(result)
        except ValidationError as exc:
            errors.append({"index": i, "errors": exc.errors()})
        except Exception as exc:
            errors.append({"index": i, "error": str(exc)})

    return {
        "processed": len(results),
        "failed": len(errors),
        "results": results,
        "errors": errors,
    }
