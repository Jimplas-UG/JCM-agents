"""
Backfill trade_closed events from MT5 deal history into JCM (observability only).

Matches open TradeEvent rows by mt5_ticket in raw_payload. Does not change BSv3.2.
"""

from __future__ import annotations

import asyncio
import sys
import uuid
from datetime import datetime, timezone
from decimal import Decimal

import httpx
from sqlalchemy import select

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.models.tables import TradeEvent, TradeOutcome
from app.services.event_pipeline import EventPipeline


async def _fetch_deals(mt5_url: str, limit: int = 200) -> list[dict]:
    async with httpx.AsyncClient(timeout=20.0) as client:
        r = await client.get(f"{mt5_url.rstrip('/')}/api/logs", params={"limit": limit})
        r.raise_for_status()
        data = r.json()
        return data.get("deals") or []


async def run_backfill(*, dry_run: bool = False) -> dict:
    settings = get_settings()
    mt5_url = settings.mt5_api_url or "http://127.0.0.1:8765"
    deals = await _fetch_deals(mt5_url)
    closed = 0
    skipped = 0
    errors: list[str] = []

    async with AsyncSessionLocal() as db:
        open_r = await db.execute(
            select(TradeEvent).where(TradeEvent.outcome == TradeOutcome.open)
        )
        open_trades = list(open_r.scalars().all())
        open_by_ticket: dict[int, TradeEvent] = {}
        for t in open_trades:
            ticket = (t.raw_payload or {}).get("mt5_ticket")
            if ticket is not None:
                open_by_ticket[int(ticket)] = t

        pipeline = EventPipeline(db)
        # MT5: entry=1 (OUT) closes a position; match position_id or order to open mt5_ticket.
        out_entry = 1
        for deal in deals:
            if int(deal.get("entry") or 0) != out_entry:
                continue
            trade = None
            for key in (deal.get("position_id"), deal.get("order")):
                if key is None:
                    continue
                t = int(key)
                if t in open_by_ticket:
                    trade = open_by_ticket[t]
                    ticket = t
                    break
            if trade is None:
                continue
            profit = float(deal.get("profit") or 0)
            price = float(deal.get("price") or 0)
            if profit == 0 and price == 0:
                skipped += 1
                continue
            outcome = "win" if profit > 0.01 else "loss" if profit < -0.01 else "breakeven"
            payload = {
                "event_id": f"backfill-close-{uuid.uuid4().hex[:12]}",
                "event_type": "trade_closed",
                "symbol": trade.symbol,
                "direction": (
                    trade.direction.value
                    if hasattr(trade.direction, "value")
                    else str(trade.direction)
                ),
                "lot_size": float(trade.lot_size or 0),
                "entry_price": float(trade.entry_price or 0),
                "exit_price": price,
                "pnl_usd": profit,
                "outcome": outcome,
                "raw_payload": {
                    "mt5_ticket": ticket,
                    "open_event_id": trade.event_id,
                    "backfill": True,
                    "closed_at": datetime.now(timezone.utc).isoformat(),
                },
            }
            if dry_run:
                closed += 1
                continue
            try:
                await pipeline.ingest("trade_closed", payload)
                closed += 1
            except Exception as exc:
                errors.append(f"{ticket}: {exc}")
        if not dry_run:
            await db.commit()

    return {"closed": closed, "skipped": skipped, "errors": errors, "deals_seen": len(deals)}


def main() -> None:
    dry = "--dry-run" in sys.argv
    result = asyncio.run(run_backfill(dry_run=dry))
    print(result)
    if result.get("errors"):
        sys.exit(1)


if __name__ == "__main__":
    main()
