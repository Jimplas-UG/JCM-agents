"""Build the daily CEO executive briefing from all 9 agents."""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.services.executive_briefing.context import load_briefing_context
from app.services.executive_briefing.markdown import render_executive_briefing
from app.services.executive_briefing.reporters import build_all_agent_reports
from app.services.executive_briefing.synthesis import (
    build_action_board,
    build_commander_assessment,
    build_decision_board,
    build_executive_summary,
    build_strategic_synthesis,
    overall_mission_status,
)
from app.services.executive_briefing.types import ExecutiveBriefingDocument


async def build_executive_briefing(
    db: AsyncSession, briefing_date: date | None = None
) -> ExecutiveBriefingDocument:
    settings = get_settings()
    today = briefing_date or date.today()
    ctx = await load_briefing_context(db, today)
    reports = build_all_agent_reports(ctx)
    mission_status = overall_mission_status(reports, ctx)

    actions = build_action_board(ctx, reports)
    doc: ExecutiveBriefingDocument = {
        "format_version": 2,
        "title": "JCM MISSION CONTROL\nDAILY EXECUTIVE BRIEFING",
        "briefing_date": str(today),
        "prepared_for": f"{settings.executive_briefing_ceo_name}, CEO\nJimplas Capital Management",
        "mission_status": mission_status,
        "executive_summary": build_executive_summary(ctx, reports, mission_status),
        "agent_reports": reports,
        "ceo_strategic_synthesis": build_strategic_synthesis(ctx, reports),
        "ceo_action_board": actions,
        "ceo_decision_board": build_decision_board(ctx, reports),
        "commander_assessment": build_commander_assessment(ctx, reports, actions),
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
    doc["rendered_markdown"] = render_executive_briefing(doc)
    return doc


def briefing_to_legacy_payload(doc: ExecutiveBriefingDocument, ctx: Any = None) -> dict[str, Any]:
    """Backward-compatible fields for dashboard widgets."""
    from app.services.executive_briefing.context import BriefingContext

    c: BriefingContext | None = ctx
    state = c.state if c else None
    risk = c.risk if c else None
    infra = c.infra if c else None
    perf = c.perf_today if c else None

    return {
        "format_version": doc.get("format_version", 2),
        "briefing_date": doc.get("briefing_date"),
        "generated_at": doc.get("generated_at"),
        "mission_status": doc.get("mission_status"),
        "executive_summary": doc.get("executive_summary"),
        "executive_briefing": doc,
        "rendered_markdown": doc.get("rendered_markdown"),
        "prepared_for": doc.get("prepared_for"),
        "agent_reports": doc.get("agent_reports"),
        "ceo_strategic_synthesis": doc.get("ceo_strategic_synthesis"),
        "ceo_action_board": doc.get("ceo_action_board"),
        "ceo_decision_board": doc.get("ceo_decision_board"),
        "commander_assessment": doc.get("commander_assessment"),
        "bsv32_system": {
            "status": state.bsv32_status if state else "unknown",
            "running": state.bsv32_status == "running" if state else False,
            "nfp_blackout": state.nfp_blackout if state else False,
            "market_regime": str(state.market_regime) if state and state.market_regime else "unknown",
        },
        "pnl": {
            "live_pnl": float(state.floating_pnl or 0) if state else 0,
            "daily_pnl": float(state.daily_pnl or 0) if state else 0,
            "open_positions": state.open_positions if state else 0,
            "account_equity": float(state.account_equity or 0) if state else 0,
        },
        "risk": {
            "risk_score": float(risk.risk_score or 0) if risk else 0,
            "drawdown_pct": float(risk.account_drawdown_pct or 0) if risk else 0,
            "kill_switch_recommended": risk.kill_switch_recommended if risk else False,
            "lot_scaling_factor": float(risk.lot_scaling_factor or 1) if risk else 1,
        },
        "infrastructure": {
            "health_score": 1.0 if (c and c.infra_live and c.infra_live.get("healthy")) else 0.5,
            "mt5_connected": infra.mt5_connected if infra else False,
            "desk_api_ok": infra.desk_api_ok if infra else False,
            "forward_bot_ok": infra.forward_bot_ok if infra else False,
            "watchdog_ok": infra.watchdog_ok if infra else False,
            "vps_cpu_pct": float(infra.vps_cpu_pct or 0) if infra else 0,
        },
        "performance_vs_baseline": {
            "win_rate": float(perf.win_rate or 0) if perf else None,
            "expectancy": float(perf.expectancy or 0) if perf else None,
            "edge_decay_score": float(perf.edge_decay_score or 0) if perf else None,
            "anomaly_flags": perf.anomaly_flags if perf else [],
        },
        "alerts": [],
        "pending_human_decisions": [],
        "pending_marketing_content": [],
    }
