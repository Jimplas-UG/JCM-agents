"""CEO Copilot Agent — daily executive briefing for Billy Jimplas, CEO."""

import json
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.db.redis_client import CHANNEL_DASHBOARD, publish
from app.models.tables import Alert, AlertSeverity, CeoBriefing
from app.services.executive_briefing.context import load_briefing_context
from app.services.executive_briefing.service import build_executive_briefing, briefing_to_legacy_payload
from app.services.live_dashboard import build_live_overview


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

    async def get_dashboard_overview(self, *, live: bool = True) -> dict[str, Any]:
        """Read-only overview — MT5 live P&L/positions when bridge is connected."""
        if live:
            return await build_live_overview(self.db, use_mt5=True)
        return await build_live_overview(self.db, use_mt5=False)

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
