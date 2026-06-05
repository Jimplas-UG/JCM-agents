"""Close JCM open rows with no MT5 ticket after backfill (allocator reconciliation)."""

from __future__ import annotations

import asyncio
import uuid
from datetime import datetime, timezone

from sqlalchemy import select

from app.db.session import AsyncSessionLocal
from app.models.tables import TradeEvent, TradeOutcome
from app.services.event_pipeline import EventPipeline


async def run_close_stale(*, dry_run: bool = False) -> dict:
    closed = 0
    async with AsyncSessionLocal() as db:
        rows = await db.execute(select(TradeEvent).where(TradeEvent.outcome == TradeOutcome.open))
        opens = list(rows.scalars().all())
        pipeline = EventPipeline(db)
        for t in opens:
            ticket = (t.raw_payload or {}).get("mt5_ticket")
            if ticket is not None:
                continue
            payload = {
                "event_id": f"stale-close-{uuid.uuid4().hex[:12]}",
                "event_type": "trade_closed",
                "symbol": t.symbol,
                "direction": t.direction.value if hasattr(t.direction, "value") else str(t.direction),
                "outcome": "cancelled",
                "pnl_usd": 0.0,
                "exit_price": float(t.entry_price or 0),
                "closed_at": datetime.now(timezone.utc).isoformat(),
                "note": "stale_open_no_mt5_ticket",
            }
            if dry_run:
                closed += 1
                continue
            await pipeline.ingest("trade_closed", payload)
            closed += 1
        if not dry_run:
            await db.commit()
    return {"stale_closed": closed, "dry_run": dry_run}


def main() -> None:
    dry = "--dry-run" in __import__("sys").argv
    print(asyncio.run(run_close_stale(dry_run=dry)))


if __name__ == "__main__":
    main()
