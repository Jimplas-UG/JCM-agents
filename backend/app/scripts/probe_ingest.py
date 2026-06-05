"""One-off ingest probe for VPS debugging."""

from __future__ import annotations

import asyncio
import sys

import httpx
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from app.config import get_settings


async def main() -> None:
    settings = get_settings()
    url = "http://127.0.0.1:8000/ingest/event"
    secret = settings.event_webhook_secret or ""
    body = {
        "event_type": "trade_executed",
        "payload": {
            "event_id": "debug-probe-001",
            "event_type": "trade_executed",
            "symbol": "XAUUSD",
            "direction": "long",
            "lot_size": 0.01,
            "entry_price": 3350.0,
            "filled_price": 3350.0,
            "outcome": "open",
            "bsv32_version": "3.2",
            "raw_payload": {"mt5_ticket": 99999, "setup": "debug"},
        },
    }
    async with httpx.AsyncClient(timeout=20.0) as client:
        r = await client.post(
            url,
            json=body,
            headers={"X-Webhook-Secret": secret},
        )
        print({"status": r.status_code, "body": r.text[:800]})


if __name__ == "__main__":
    asyncio.run(main())
