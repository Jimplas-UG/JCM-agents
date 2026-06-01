"""CEO Copilot Agent — daily executive briefing for Billy Jimplas, CEO."""

import json
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.db.redis_client import CHANNEL_DASHBOARD, publish
from app.models.tables import Alert, AlertSeverity, CeoBriefing, InfraHealthLog
from app.services.executive_briefing.context import load_briefing_context
from app.services.executive_briefing.service import build_executive_briefing, briefing_to_legacy_payload


class CeoCopilotAgent(BaseAgent):
    name = "ceo_copilot"
    description = "Daily executive briefing and mission-control dashboard data"

    async def run_cycle(self) -> dict[str, Any]:
        briefing = await self.generate_daily_briefing()
        await publish(CHANNEL_DASHBOARD, json.dumps(briefing, default=str))
        return {
            "status": "ok",
            "briefing_date": str(briefing.get("briefing_date")),
            "mission_status": briefing.get("mission_status"),
        }

    async def generate_daily_briefing(self, briefing_date: date | None = None) -> dict[str, Any]:
        today = briefing_date or date.today()
        doc = await build_executive_briefing(self.db, today)
        ctx = await load_briefing_context(self.db, today)
        briefing = briefing_to_legacy_payload(doc, ctx)

        briefing["alerts"] = [
            {
                "id": str(a.id),
                "severity": (
                    a.severity.value if isinstance(a.severity, AlertSeverity) else str(a.severity)
                ),
                "title": a.title,
                "created_at": a.created_at.isoformat(),
            }
            for a in ctx.alerts_open[:20]
        ]
        briefing["pending_human_decisions"] = [
            {
                "id": str(r.id),
                "title": r.title,
                "finding_type": r.finding_type,
                "severity": str(r.severity),
            }
            for r in ctx.research_pending[:10]
        ]
        briefing["pending_marketing_content"] = [
            {
                "id": str(m.id),
                "title": m.title,
                "platform": m.platform,
                "content_type": m.content_type,
                "status": m.status,
            }
            for m in ctx.marketing_drafts[:10]
        ]

        await self._persist_briefing(today, briefing, ctx)
        return briefing

    async def get_dashboard_overview(self) -> dict[str, Any]:
        """Read-only overview — no briefing persistence on dashboard poll."""
        ctx = await load_briefing_context(self.db)
        state = ctx.state
        risk = ctx.risk
        infra = ctx.infra

        market_regime = "unknown"
        if state and state.market_regime is not None:
            market_regime = (
                state.market_regime.value
                if hasattr(state.market_regime, "value")
                else str(state.market_regime)
            )

        return {
            "bsv32_status": state.bsv32_status if state else "unknown",
            "system_running": state.bsv32_status == "running" if state else False,
            "nfp_blackout": state.nfp_blackout if state else False,
            "live_pnl": float(state.floating_pnl or 0) if state else 0,
            "floating_pnl": float(state.floating_pnl or 0) if state else 0,
            "daily_pnl": float(state.daily_pnl or 0) if state else 0,
            "open_positions": state.open_positions if state else 0,
            "risk_score": float(risk.risk_score or 0) if risk else 0,
            "market_regime": market_regime,
            "infra_health_score": self._infra_health_score(infra),
            "active_alerts": len(ctx.alerts_open),
            "pending_reviews": len(ctx.research_pending),
            "pending_marketing_drafts": len(ctx.marketing_drafts),
            "mt5_connected": infra.mt5_connected if infra else False,
            "last_updated": datetime.now(timezone.utc),
        }

    def _infra_health_score(self, infra: InfraHealthLog | None) -> float:
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

    async def _persist_briefing(self, today: date, briefing: dict, ctx: Any) -> None:
        state = ctx.state
        risk = ctx.risk
        infra = ctx.infra
        alerts = ctx.alerts_open
        reviews = ctx.research_pending

        existing = await self.db.execute(
            select(CeoBriefing).where(CeoBriefing.briefing_date == today)
        )
        row = existing.scalar_one_or_none()
        if row is None:
            row = CeoBriefing(briefing_date=today)
            self.db.add(row)

        row.briefing_json = briefing
        row.system_status = state.bsv32_status if state else "unknown"
        row.live_pnl = Decimal(str(briefing["pnl"]["live_pnl"]))
        row.risk_score = Decimal(str(briefing["risk"]["risk_score"]))
        row.infra_health_score = Decimal(str(self._infra_health_score(infra)))
        row.active_alerts_count = len(alerts)
        row.pending_reviews = len(reviews)
        await self.db.flush()
