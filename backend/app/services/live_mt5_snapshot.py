"""Read-only MT5 bridge snapshot for Mission Control live metrics."""

from __future__ import annotations

from typing import Any

import httpx

from app.config import get_settings
from app.logging_config import get_logger

logger = get_logger(__name__)


async def fetch_mt5_snapshot() -> dict[str, Any] | None:
    """Fetch account + positions from the Bilshenz MT5 API (no strategy logic)."""
    settings = get_settings()
    base = (settings.mt5_api_url or "").rstrip("/")
    if not base:
        return None

    headers: dict[str, str] = {}
    if settings.mt5_api_key:
        headers["Authorization"] = f"Bearer {settings.mt5_api_key}"

    timeout = httpx.Timeout(4.0, connect=2.0)
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            status_resp = await client.get(f"{base}/api/status", headers=headers)
            if status_resp.status_code != 200:
                logger.warning("mt5_status_http_error", status=status_resp.status_code)
                return None
            status = status_resp.json()
            positions: list[dict[str, Any]] = []
            if status.get("connected"):
                pos_resp = await client.get(f"{base}/api/positions", headers=headers)
                if pos_resp.status_code == 200:
                    body = pos_resp.json()
                    positions = list(body.get("positions") or [])

        account = status.get("account") or {}
        floating = float(account.get("profit") or 0)
        equity = float(account.get("equity") or 0)
        balance = float(account.get("balance") or 0)

        return {
            "connected": bool(status.get("connected")),
            "trade_allowed": bool(status.get("trade_allowed")),
            "terminal_trade_allowed": bool(status.get("terminal_trade_allowed")),
            "account": {
                "login": account.get("login"),
                "server": account.get("server"),
                "equity": equity,
                "balance": balance,
                "profit": floating,
                "currency": account.get("currency"),
            },
            "positions": positions,
            "open_positions": len(positions),
            "floating_pnl": floating,
            "account_equity": equity,
            "account_balance": balance,
        }
    except Exception as exc:
        logger.warning("mt5_snapshot_failed", error=str(exc))
        return None
