"""Event ingestion endpoints — receive BSv3.2 events from execution layer."""

from typing import Any

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, verify_webhook_secret
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
    result = await pipeline.ingest(event_type, payload)

    symbol = payload.get("symbol", "unknown")
    if event_type in ("trade_executed", "trade_closed"):
        TRADE_EVENTS_TOTAL.labels(event_type=event_type, symbol=symbol).inc()
    elif event_type == "trade_blocked":
        for f in payload.get("blocked_by", []):
            FILTER_BLOCKS_TOTAL.labels(filter=f).inc()

    return result


@router.post("/batch", dependencies=[Depends(verify_webhook_secret)])
async def ingest_batch(
    body: dict[str, Any],
    db: AsyncSession = Depends(get_db_session),
) -> dict[str, Any]:
    events = body.get("events", [])
    pipeline = EventPipeline(db)
    results = []
    for event in events:
        event_type = event.get("event_type", "unknown")
        payload = event.get("payload", event)
        result = await pipeline.ingest(event_type, payload)
        results.append(result)
    return {"processed": len(results), "results": results}
