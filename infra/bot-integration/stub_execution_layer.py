"""
Minimal BSv3.2 execution-layer stubs for local integration testing.

Runs mt5-bridge (8081), desk-api (8082), forward-bot (8083), watchdog (8084).
Replace with production services when available.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

# Load integration env (same vars as forward-bot production)
_ENV_FILE = Path(__file__).resolve().parent / "bsv32-forward-bot.env"
load_dotenv(_ENV_FILE)

MT5_KEY = os.getenv("MT5_API_KEY", "")
DESK_KEY = os.getenv("DESK_API_KEY", "")
FWD_KEY = os.getenv("FORWARD_BOT_API_KEY", "")
WD_KEY = os.getenv("WATCHDOG_API_KEY", "")


def _auth(api_key: str, authorization: str | None) -> None:
    if api_key and authorization != f"Bearer {api_key}":
        raise HTTPException(status_code=401, detail="Unauthorized")


def _health_app(name: str, api_key: str) -> FastAPI:
    app = FastAPI(title=name)

    @app.get("/health")
    async def health(authorization: str | None = Header(default=None)) -> dict:
        _auth(api_key, authorization)
        return {"status": "ok", "service": name}

    return app


mt5_app = _health_app("mt5-bridge", MT5_KEY)


@mt5_app.get("/ping")
async def ping() -> dict:
    return {"pong": True}


desk_app = _health_app("desk-api", DESK_KEY)

forward_app = _health_app("forward-bot", FWD_KEY)

watchdog_app = _health_app("watchdog", WD_KEY)


@watchdog_app.get("/vps/metrics")
async def vps_metrics(authorization: str | None = Header(default=None)) -> dict:
    _auth(WD_KEY, authorization)
    try:
        import psutil

        return {
            "cpu_pct": float(psutil.cpu_percent(interval=0.2)),
            "ram_pct": float(psutil.virtual_memory().percent),
            "disk_pct": float(psutil.disk_usage("C:\\").percent),
            "source": "psutil",
        }
    except Exception:
        return {"cpu_pct": 0.0, "ram_pct": 0.0, "disk_pct": 0.0, "source": "unavailable"}


@watchdog_app.post("/remediate/{service}")
async def remediate(service: str, authorization: str | None = Header(default=None)) -> dict:
    """Restart Bilshenz scheduled tasks when JCM infra agent requests remediation."""
    import subprocess

    _auth(WD_KEY, authorization)
    task_map = {
        "mt5": "Bilshenz-MT5-API",
        "desk": "Bilshenz-DeskAPI",
        "forward_bot": "Bilshenz-ForwardBot",
        "watchdog": "Bilshenz-Watchdog",
    }
    task = task_map.get(service)
    if not task:
        raise HTTPException(status_code=404, detail=f"Unknown service: {service}")
    try:
        subprocess.run(
            ["schtasks", "/Run", "/TN", task],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        return {"ok": True, "service": service, "task": task}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


class WebhookEmitBody(BaseModel):
  event_type: str = "trade_executed"
  use_sample: bool = True


@forward_app.post("/emit-event")
async def emit_event(
    body: WebhookEmitBody,
    authorization: str | None = Header(default=None),
) -> dict:
    """Emit a test event to JCM (simulates forward-bot webhook)."""
    import httpx
    from datetime import datetime, timezone

    _auth(FWD_KEY, authorization)

    webhook_url = os.getenv("JCM_INGEST_WEBHOOK_URL", "http://127.0.0.1:8000/ingest/event")
    secret = os.getenv("JCM_WEBHOOK_SECRET", "")

    payload = {
        "event_type": body.event_type,
        "payload": {
            "event_id": f"fwd-stub-{datetime.now(timezone.utc).timestamp()}",
            "event_type": body.event_type,
            "symbol": "XAUUSD",
            "direction": "long",
            "lot_size": 0.1,
            "entry_price": 2345.50,
            "filled_price": 2345.62,
            "outcome": "open",
            "filter_states": {"nfp_blackout": "passed", "yield_filter": "passed"},
            "filters_passed": ["nfp_blackout", "yield_filter"],
            "market_regime": "trending_bull",
            "trading_session": "london",
            "bsv32_confidence": 0.82,
            "vps_health": {"cpu_pct": 42, "ram_pct": 58, "disk_pct": 35, "mt5_connected": True},
        },
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(
            webhook_url,
            json=payload,
            headers={"X-Webhook-Secret": secret},
        )
    return {"webhook_url": webhook_url, "status_code": resp.status_code, "body": resp.text}


SERVICES = [
    ("mt5-bridge", mt5_app, 8081),
    ("desk-api", desk_app, 8082),
    ("forward-bot", forward_app, 8083),
    ("watchdog", watchdog_app, 8084),
]


def main() -> None:
    import uvicorn

    if len(sys.argv) < 2:
        print("Usage: python stub_execution_layer.py <mt5|desk|forward|watchdog|all>")
        sys.exit(1)

    target = sys.argv[1].lower()
    if target == "all":
        import multiprocessing

        def run(name: str, app: FastAPI, port: int) -> None:
            uvicorn.run(app, host="0.0.0.0", port=port, log_level="warning")

        procs = []
        for name, app, port in SERVICES:
            p = multiprocessing.Process(target=run, args=(name, app, port), daemon=True)
            p.start()
            procs.append(p)
            print(f"Started {name} on :{port} (pid {p.pid})")
        for p in procs:
            p.join()
    else:
        mapping = {
            "mt5": SERVICES[0],
            "desk": SERVICES[1],
            "forward": SERVICES[2],
            "watchdog": SERVICES[3],
        }
        if target not in mapping:
            print(f"Unknown service: {target}")
            sys.exit(1)
        name, app, port = mapping[target]
        uvicorn.run(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
