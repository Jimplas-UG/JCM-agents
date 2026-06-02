#!/usr/bin/env python3
"""Load-test BSv3.2 ingest — 10 concurrent workers, synthetic trade events."""

from __future__ import annotations

import argparse
import asyncio
import os
import time
import uuid

import httpx

DEFAULT_BASE = os.environ.get("JCM_API_URL", "http://127.0.0.1:8000")
DEFAULT_SECRET = os.environ.get("EVENT_WEBHOOK_SECRET", "")


def _trade_payload(i: int) -> dict:
    eid = f"loadtest-{uuid.uuid4().hex[:12]}-{i}"
    return {
        "event_type": "trade_executed",
        "payload": {
            "event_id": eid,
            "symbol": "XAUUSD",
            "direction": "buy",
            "volume": 0.01,
            "price": 2350.0 + (i % 10) * 0.1,
            "timestamp": time.time(),
            "strategy": "BSv3.2",
            "session": "P2",
        },
    }


async def _post_one(
    client: httpx.AsyncClient,
    base: str,
    secret: str,
    i: int,
) -> tuple[int, float, str | None]:
    t0 = time.perf_counter()
    try:
        r = await client.post(
            f"{base.rstrip('/')}/ingest/event",
            json=_trade_payload(i),
            headers={"X-Webhook-Secret": secret},
            timeout=30.0,
        )
        return r.status_code, time.perf_counter() - t0, None
    except Exception as exc:
        return 0, time.perf_counter() - t0, str(exc)


async def run_load(
    *,
    base: str,
    secret: str,
    total: int,
    concurrency: int,
) -> None:
    if not secret:
        raise SystemExit("Set EVENT_WEBHOOK_SECRET or pass --secret")

    sem = asyncio.Semaphore(concurrency)
    latencies: list[float] = []
    ok = fail = 0

    async with httpx.AsyncClient() as client:

        async def worker(i: int) -> None:
            nonlocal ok, fail
            async with sem:
                code, elapsed, err = await _post_one(client, base, secret, i)
                latencies.append(elapsed)
                if code == 200:
                    ok += 1
                else:
                    fail += 1
                    if err:
                        print(f"  [{i}] error: {err}")
                    else:
                        print(f"  [{i}] HTTP {code}")

        await asyncio.gather(*[worker(i) for i in range(total)])

    latencies.sort()
    p50 = latencies[len(latencies) // 2] if latencies else 0
    p95 = latencies[int(len(latencies) * 0.95)] if latencies else 0
    print(f"\nIngest load test: {total} events, concurrency={concurrency}")
    print(f"  OK: {ok}  Failed: {fail}")
    print(f"  Latency p50: {p50*1000:.1f}ms  p95: {p95*1000:.1f}ms")


def main() -> None:
    p = argparse.ArgumentParser(description="JCM ingest load test")
    p.add_argument("--base", default=DEFAULT_BASE)
    p.add_argument("--secret", default=DEFAULT_SECRET)
    p.add_argument("--count", type=int, default=100, help="Total events (default 100)")
    p.add_argument("--concurrency", type=int, default=10, help="Parallel workers")
    args = p.parse_args()
    asyncio.run(
        run_load(
            base=args.base,
            secret=args.secret,
            total=args.count,
            concurrency=args.concurrency,
        )
    )


if __name__ == "__main__":
    main()
