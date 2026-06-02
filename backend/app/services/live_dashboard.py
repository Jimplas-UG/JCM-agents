"""Merge MT5 live facts with persisted supervisory context for Mission Control."""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.tables import TradeEvent, TradeOutcome
from app.services.executive_briefing.context import load_briefing_context
from app.services.live_mt5_snapshot import fetch_mt5_snapshot


async def _closed_pnl_today(db: AsyncSession, today: date) -> float:
    start = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    end = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc).replace(
        hour=23, minute=59, second=59, microsecond=999999
    )
    result = await db.execute(
        select(func.coalesce(func.sum(TradeEvent.pnl_usd), 0)).where(
            TradeEvent.created_at >= start,
            TradeEvent.created_at <= end,
            TradeEvent.outcome != TradeOutcome.open,
        )
    )
    return float(result.scalar() or 0)


async def build_live_overview(db: AsyncSession, *, use_mt5: bool = True) -> dict[str, Any]:
    """Overview for CEO Mission Control — MT5 live P&L/positions when bridge is up."""
    ctx = await load_briefing_context(db)
    state = ctx.state
    risk = ctx.risk
    infra = ctx.infra
    today = ctx.today

    market_regime = "unknown"
    if state and state.market_regime is not None:
        market_regime = (
            state.market_regime.value
            if hasattr(state.market_regime, "value")
            else str(state.market_regime)
        )

    mt5 = await fetch_mt5_snapshot() if use_mt5 else None
    closed_today = await _closed_pnl_today(db, today)

    floating = float(state.floating_pnl or 0) if state else 0.0
    daily = float(state.daily_pnl or 0) if state else 0.0
    open_positions = state.open_positions if state else 0
    mt5_connected = infra.mt5_connected if infra else False
    account_equity = float(state.account_equity or 0) if state and state.account_equity else None
    data_source = "database"

    if mt5 and mt5.get("connected"):
        floating = float(mt5.get("floating_pnl") or 0)
        open_positions = int(mt5.get("open_positions") or 0)
        mt5_connected = True
        account_equity = float(mt5.get("account_equity") or 0)
        daily = closed_today + floating
        data_source = "mt5_live"

    return {
        "bsv32_status": state.bsv32_status if state else "unknown",
        "system_running": state.bsv32_status == "running" if state else False,
        "nfp_blackout": state.nfp_blackout if state else False,
        "live_pnl": floating,
        "floating_pnl": floating,
        "daily_pnl": daily,
        "open_positions": open_positions,
        "account_equity": account_equity,
        "risk_score": float(risk.risk_score or 0) if risk else 0,
        "market_regime": market_regime,
        "infra_health_score": _infra_health_score(infra),
        "active_alerts": len(ctx.alerts_open),
        "pending_reviews": len(ctx.research_pending),
        "pending_marketing_drafts": len(ctx.marketing_drafts),
        "mt5_connected": mt5_connected,
        "data_source": data_source,
        "last_updated": datetime.now(timezone.utc),
        "positions": (mt5 or {}).get("positions") or [],
    }


def _infra_health_score(infra: Any) -> float:
    if not infra:
        return 0.0
    score = 1.0
    if not infra.mt5_connected:
        score -= 0.3
    if not infra.desk_api_ok:
        score -= 0.2
    if not infra.forward_bot_ok:
        score -= 0.2
    if float(infra.vps_cpu_pct or 0) > 85:
        score -= 0.15
    if float(infra.vps_ram_pct or 0) > 85:
        score -= 0.15
    return round(max(0, score), 2)
