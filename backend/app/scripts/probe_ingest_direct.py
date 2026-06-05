"""Direct pipeline probe — surfaces exception tracebacks on VPS."""

from __future__ import annotations

import asyncio
import traceback


async def main() -> None:
    from app.db.session import AsyncSessionLocal
    from app.services.event_pipeline import EventPipeline

    payload = {
        "event_id": "debug-direct-001",
        "event_type": "trade_executed",
        "symbol": "XAUUSD",
        "direction": "long",
        "lot_size": 0.01,
        "entry_price": 3350.0,
        "filled_price": 3350.0,
        "outcome": "open",
        "bsv32_version": "3.2",
        "raw_payload": {"mt5_ticket": 99999, "setup": "debug"},
    }
    async with AsyncSessionLocal() as db:
        pipeline = EventPipeline(db)
        try:
            result = await pipeline.ingest("trade_executed", payload)
            await db.commit()
            print("OK", result)
        except Exception:
            traceback.print_exc()
            await db.rollback()


if __name__ == "__main__":
    asyncio.run(main())
