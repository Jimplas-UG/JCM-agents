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
from app.services.agent_guard import validate_briefing_against_snapshot
from app.services.agent_orchestrator import publish_agent_message
from app.services.live_dashboard import _infra_health_score, build_live_overview
from app.services.mission_memory import load_mission_snapshot


class CeoCopilotAgent(BaseAgent):
    name = "ceo_copilot"
    description = "Daily executive briefing and mission-control dashboard data"

    async def run_cycle(self) -> dict[str, Any]:
        """Refresh live overview + snapshot; full briefing only once per day unless forced."""
        overview = await build_live_overview(self.db, use_mt5=True)
        await publish(
            CHANNEL_DASHBOARD,
            json.dumps(
                {
                    "type": "overview_refresh",
                    "briefing_date": str(date.today()),
                    "mission_status": overview.get("bsv32_status"),
                    "live_pnl": overview.get("live_pnl"),
                },
                default=str,
            ),
        )
        return {
            "status": "ok",
            "mode": "overview_refresh",
            "briefing_date": str(date.today()),
            "system_running": overview.get("system_running"),
            "risk_score": overview.get("risk_score"),
            "infra_health_score": overview.get("infra_health_score"),
            "active_alerts": overview.get("active_alerts"),
        }

    async def generate_daily_briefing(
        self, briefing_date: date | None = None, *, force: bool = False
    ) -> dict[str, Any]:
        today = briefing_date or date.today()

        if not force:
            existing = await self.db.execute(
                select(CeoBriefing).where(CeoBriefing.briefing_date == today)
            )
            row = existing.scalar_one_or_none()
            if row and row.briefing_json:
                cached = dict(row.briefing_json)
                cached["from_cache"] = True
                return cached

        doc, ctx = await build_executive_briefing(self.db, today)
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

        snapshot = await load_mission_snapshot() or {}
        validation = validate_briefing_against_snapshot(
            briefing,
            {
                "live_pnl": snapshot.get("live_pnl"),
                "floating_pnl": snapshot.get("live_pnl"),
                "risk_score": snapshot.get("risk_score"),
            },
        )
        briefing["validation"] = validation
        if not validation.get("verified"):
            await publish_agent_message(
                self.name,
                "briefing_validation_warning",
                validation,
                priority="high",
            )

        await self._persist_briefing(today, briefing, ctx)
        briefing["from_cache"] = False
        return briefing

    async def get_dashboard_overview(self, *, live: bool = True) -> dict[str, Any]:
        return await build_live_overview(self.db, use_mt5=live)

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
        row.infra_health_score = Decimal(str(_infra_health_score(infra)))
        row.active_alerts_count = len(alerts)
        row.pending_reviews = len(reviews)
        await self.db.flush()
