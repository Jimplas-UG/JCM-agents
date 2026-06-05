"""Reconcile JCM TradeEvent rows against MT5 deal history."""

from __future__ import annotations

import asyncio
import sys

import httpx
from sqlalchemy import select

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.models.tables import TradeEvent, TradeOutcome


async def run_reconcile() -> dict:
    settings = get_settings()
    mt5_url = settings.mt5_api_url or "http://127.0.0.1:8765"
    async with httpx.AsyncClient(timeout=20.0) as client:
        deals_r = await client.get(f"{mt5_url.rstrip('/')}/api/logs", params={"limit": 100})
        deals_r.raise_for_status()
        deals = deals_r.json().get("deals") or []

    async with AsyncSessionLocal() as db:
        rows = await db.execute(select(TradeEvent))
        trades = list(rows.scalars().all())

    open_jcm = [t for t in trades if t.outcome == TradeOutcome.open]
    mt5_tickets = {
        int(d.get("position_id") or d.get("order") or 0)
        for d in deals
        if int(d.get("entry") or 0) == 1
    }
    mt5_tickets.discard(0)

    matched = 0
    for t in open_jcm:
        ticket = (t.raw_payload or {}).get("mt5_ticket")
        if ticket is not None and int(ticket) in mt5_tickets:
            matched += 1

    stale_open = len(open_jcm) > 0 and matched == 0
    return {
        "jcm_open": len(open_jcm),
        "jcm_total": len(trades),
        "mt5_close_deals": len(mt5_tickets),
        "matched_open_to_mt5": matched,
        "ok": len(open_jcm) == 0 or matched == len(open_jcm),
        "stale_open_records": stale_open,
        "note": "Run backfill_trade_closed_from_mt5 if stale_open_records" if stale_open else None,
    }


def main() -> None:
    result = asyncio.run(run_reconcile())
    print(result)
    if not result.get("ok") and not result.get("stale_open_records"):
        sys.exit(1)


if __name__ == "__main__":
    main()
