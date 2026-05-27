#!/usr/bin/env python3
"""Sample script to test BSv3.2 event ingestion webhook."""

import json
import os
import sys
from datetime import datetime, timezone

import httpx

API_URL = os.getenv("API_URL", "http://localhost:8000")
WEBHOOK_SECRET = os.getenv("EVENT_WEBHOOK_SECRET", "change-me-webhook-secret")


def send_trade_executed() -> None:
    payload = {
        "event_type": "trade_executed",
        "payload": {
            "event_id": f"test-{datetime.now(timezone.utc).timestamp()}",
            "event_type": "trade_executed",
            "symbol": "XAUUSD",
            "direction": "long",
            "lot_size": 0.1,
            "entry_price": 2345.50,
            "filled_price": 2345.62,
            "requested_price": 2345.50,
            "slippage_pips": 1.2,
            "spread_at_entry": 2.5,
            "spread_avg_24h": 2.1,
            "execution_latency_ms": 340,
            "outcome": "open",
            "filter_states": {
                "nfp_blackout": "passed",
                "yield_filter": "passed",
                "dxy_filter": "passed",
                "ath_zone": "passed",
                "geopolitical": "passed",
                "chop_zone": "passed",
                "buy_path": "passed",
                "risk_gating": "passed",
            },
            "filters_passed": [
                "nfp_blackout", "yield_filter", "dxy_filter",
                "buy_path", "risk_gating",
            ],
            "market_regime": "trending_bull",
            "trading_session": "london",
            "dxy_value": 104.25,
            "dxy_state": "bullish",
            "yield_10y": 4.35,
            "yield_state": "elevated",
            "bsv32_confidence": 0.82,
            "vps_health": {"cpu_pct": 45, "ram_pct": 62, "disk_pct": 38, "mt5_connected": True},
        },
    }
    resp = httpx.post(
        f"{API_URL}/ingest/event",
        json=payload,
        headers={"X-Webhook-Secret": WEBHOOK_SECRET},
        timeout=10.0,
    )
    print(f"Status: {resp.status_code}")
    print(json.dumps(resp.json(), indent=2))


if __name__ == "__main__":
    send_trade_executed()
