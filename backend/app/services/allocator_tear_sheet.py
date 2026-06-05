"""LP tear sheet — allocator due-diligence factsheet from live + research data."""

from __future__ import annotations

import json
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.tables import PerformanceDaily, TradeEvent, TradeOutcome
from app.services.allocator_readiness import build_allocator_readiness_payload


def _latest_backtest_summary() -> dict[str, Any] | None:
    data = Path(r"C:\opt\bilshenz\backend\validation\data")
    if not data.is_dir():
        return None
    files = sorted(data.glob("*realistic-mt5*output.txt"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        return None
    text = files[0].read_text(encoding="utf-8", errors="replace")
    import re

    def _f(pat: str) -> float | None:
        m = re.search(pat, text, re.I)
        return float(m.group(1)) if m else None

    def _i(pat: str) -> int | None:
        m = re.search(pat, text, re.I)
        return int(m.group(1)) if m else None

    return {
        "report_file": str(files[0]),
        "window": "12 months realistic MT5",
        "starting_equity": _f(r"Starting equity:\s*\$?([\d.]+)"),
        "ending_equity": _f(r"Ending equity[^:]*:\s*\$?([\d.]+)"),
        "net_pct": _f(r"\(\+?([-\d.]+)%\)"),
        "profit_factor": _f(r"Profit factor[^:]*:\s*([\d.]+)"),
        "win_rate_pct": _f(r"Win rate \(closed\):\s*([\d.]+)"),
        "trades": _i(r"Closed in window:\s*(\d+)"),
        "max_drawdown_usd": _f(r"Max drawdown[^:]*:\s*\$?([\d.]+)"),
    }


async def build_allocator_tear_sheet(db: AsyncSession) -> dict[str, Any]:
    readiness = await build_allocator_readiness_payload(db)
    backtest = _latest_backtest_summary()

    closed = await db.execute(
        select(TradeEvent).where(TradeEvent.outcome != TradeOutcome.open).order_by(TradeEvent.created_at.desc())
    )
    trades = list(closed.scalars().all())

    wins = sum(1 for t in trades if t.outcome == TradeOutcome.win)
    losses = sum(1 for t in trades if t.outcome == TradeOutcome.loss)
    total_pnl = sum(float(t.pnl_usd or 0) for t in trades)
    wr = (wins / len(trades) * 100) if trades else 0.0

    perf_row = await db.execute(
        select(PerformanceDaily).order_by(PerformanceDaily.report_date.desc()).limit(1)
    )
    latest_perf = perf_row.scalar_one_or_none()

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "factsheet_date": str(date.today()),
        "firm": "Jimplas Capital Management",
        "strategy": "BSv3.2 (frozen production)",
        "symbol": "XAUUSD",
        "risk_per_trade_pct": 1.0,
        "allocator_check_ready": readiness.get("check_ready", False),
        "allocator_progress": readiness.get("progress_score", 0),
        "allocator_tier": readiness.get("tier"),
        "allocator_blockers": readiness.get("blockers", []),
        "live_track_record": {
            "closed_trades": len(trades),
            "wins": wins,
            "losses": losses,
            "win_rate_pct": round(wr, 2),
            "total_pnl_usd": round(total_pnl, 2),
            "stale_open_records": readiness.get("stale_jcm_opens", 0),
        },
        "research_attestation": backtest,
        "latest_daily_performance": (
            {
                "report_date": str(latest_perf.report_date),
                "win_rate": float(latest_perf.win_rate or 0),
                "expectancy": float(latest_perf.expectancy or 0),
                "edge_decay_score": float(latest_perf.edge_decay_score or 0),
            }
            if latest_perf
            else None
        ),
        "risk_controls": {
            "daily_loss_limit_pct": 3.0,
            "max_drawdown_halt_pct": 15.0,
            "consecutive_loss_halt": 4,
            "kill_switch_enforced": bool(readiness.get("halt", {}).get("audit_file")),
            "strategy_freeze": True,
        },
        "disclaimer": (
            "Not an offer or solicitation. Live track record is forward-demo on Exness MT5. "
            "Research attestation is realistic simulated execution. Allocator check-ready requires all gates."
        ),
    }


def write_tear_sheet_json(sheet: dict[str, Any]) -> Path:
    out_dir = Path(r"C:\opt\bilshenz\backend\validation\data")
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "allocator-tear-sheet.json"
    out.write_text(json.dumps(sheet, indent=2), encoding="utf-8")
    return out
