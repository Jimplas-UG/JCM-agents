"""CEO Copilot Agent — executive command center briefing generator."""

import json
from datetime import date, datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.db.redis_client import CHANNEL_DASHBOARD, publish
from app.models.tables import (
    Alert,
    CeoBriefing,
    InfraHealthLog,
    PerformanceDaily,
    ResearchReviewQueue,
    ReviewStatus,
    RiskExposureSnapshot,
    SystemStateSnapshot,
)


class CeoCopilotAgent(BaseAgent):
    name = "ceo_copilot"
    description = "Daily executive briefing and mission-control dashboard data"

    async def run_cycle(self) -> dict[str, Any]:
        briefing = await self.generate_daily_briefing()
        await publish(CHANNEL_DASHBOARD, json.dumps(briefing, default=str))
        return {"status": "ok", "briefing_date": str(briefing.get("briefing_date"))}

    async def generate_daily_briefing(self) -> dict[str, Any]:
        today = date.today()
        state = await self._latest_system_state()
        risk = await self._latest_risk()
        infra = await self._latest_infra()
        perf = await self._latest_performance()
        alerts = await self._active_alerts()
        reviews = await self._pending_reviews()

        briefing = {
            "briefing_date": str(today),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "bsv32_system": {
                "status": state.bsv32_status if state else "unknown",
                "running": state.bsv32_status == "running" if state else False,
                "nfp_blackout": state.nfp_blackout if state else False,
                "market_regime": state.market_regime if state else "unknown",
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
                "health_score": self._infra_health_score(infra),
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
            "alerts": [
                {
                    "id": str(a.id),
                    "severity": a.severity,
                    "title": a.title,
                    "created_at": a.created_at.isoformat(),
                }
                for a in alerts
            ],
            "pending_human_decisions": [
                {
                    "id": str(r.id),
                    "title": r.title,
                    "finding_type": r.finding_type,
                    "severity": r.severity,
                }
                for r in reviews
            ],
        }

        await self._persist_briefing(today, briefing, state, risk, infra, alerts, reviews)
        return briefing

    async def get_dashboard_overview(self) -> dict[str, Any]:
        briefing = await self.generate_daily_briefing()
        bsv32 = briefing["bsv32_system"]
        pnl = briefing["pnl"]
        risk = briefing["risk"]
        infra = briefing["infrastructure"]

        return {
            "bsv32_status": bsv32["status"],
            "system_running": bsv32["running"],
            "nfp_blackout": bsv32["nfp_blackout"],
            "live_pnl": pnl["live_pnl"],
            "floating_pnl": pnl["live_pnl"],
            "daily_pnl": pnl["daily_pnl"],
            "open_positions": pnl["open_positions"],
            "risk_score": risk["risk_score"],
            "market_regime": bsv32["market_regime"],
            "infra_health_score": infra["health_score"],
            "active_alerts": len(briefing["alerts"]),
            "pending_reviews": len(briefing["pending_human_decisions"]),
            "mt5_connected": infra["mt5_connected"],
            "last_updated": datetime.now(timezone.utc).isoformat(),
        }

    async def _latest_system_state(self) -> SystemStateSnapshot | None:
        result = await self.db.execute(
            select(SystemStateSnapshot)
            .order_by(SystemStateSnapshot.created_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def _latest_risk(self) -> RiskExposureSnapshot | None:
        result = await self.db.execute(
            select(RiskExposureSnapshot)
            .order_by(RiskExposureSnapshot.created_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def _latest_infra(self) -> InfraHealthLog | None:
        result = await self.db.execute(
            select(InfraHealthLog).order_by(InfraHealthLog.created_at.desc()).limit(1)
        )
        return result.scalar_one_or_none()

    async def _latest_performance(self) -> PerformanceDaily | None:
        result = await self.db.execute(
            select(PerformanceDaily).order_by(PerformanceDaily.report_date.desc()).limit(1)
        )
        return result.scalar_one_or_none()

    async def _active_alerts(self) -> list[Alert]:
        result = await self.db.execute(
            select(Alert)
            .where(Alert.acknowledged == False)  # noqa: E712
            .order_by(Alert.created_at.desc())
            .limit(20)
        )
        return list(result.scalars().all())

    async def _pending_reviews(self) -> list[ResearchReviewQueue]:
        result = await self.db.execute(
            select(ResearchReviewQueue)
            .where(ResearchReviewQueue.status == ReviewStatus.pending)
            .order_by(ResearchReviewQueue.created_at.desc())
            .limit(10)
        )
        return list(result.scalars().all())

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

    async def _persist_briefing(
        self,
        today: date,
        briefing: dict,
        state: SystemStateSnapshot | None,
        risk: RiskExposureSnapshot | None,
        infra: InfraHealthLog | None,
        alerts: list,
        reviews: list,
    ) -> None:
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
