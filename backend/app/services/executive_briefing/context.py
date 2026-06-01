"""Aggregate operational data for executive briefing (read-only)."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from typing import Any

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.tables import (
    Alert,
    AuditTrail,
    ExecutionQualityLog,
    InfraHealthLog,
    MarketingContentQueue,
    MarketingCycleReport,
    PerformanceDaily,
    ResearchReviewQueue,
    ReviewStatus,
    RiskExposureSnapshot,
    SystemStateSnapshot,
    TradeEvent,
)


@dataclass
class BriefingContext:
    today: date
    yesterday_start: datetime
    yesterday_end: datetime
    now: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    state: SystemStateSnapshot | None = None
    risk: RiskExposureSnapshot | None = None
    infra: InfraHealthLog | None = None
    perf_today: PerformanceDaily | None = None
    perf_yesterday: PerformanceDaily | None = None

    alerts_open: list[Alert] = field(default_factory=list)
    alerts_critical: list[Alert] = field(default_factory=list)
    research_pending: list[ResearchReviewQueue] = field(default_factory=list)
    marketing_drafts: list[MarketingContentQueue] = field(default_factory=list)
    marketing_approved: int = 0
    marketing_cycle_today: MarketingCycleReport | None = None

    trades_yesterday: list[TradeEvent] = field(default_factory=list)
    trades_today: list[TradeEvent] = field(default_factory=list)
    open_trades: list[TradeEvent] = field(default_factory=list)
    audits_yesterday: list[AuditTrail] = field(default_factory=list)
    execution_logs_24h: list[ExecutionQualityLog] = field(default_factory=list)

    infra_live: dict[str, Any] | None = None


async def load_briefing_context(db: AsyncSession, today: date | None = None) -> BriefingContext:
    today = today or date.today()
    y0 = datetime.combine(today - timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)
    y1 = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)
    t0 = y1
    t1 = datetime.combine(today + timedelta(days=1), datetime.min.time(), tzinfo=timezone.utc)

    ctx = BriefingContext(
        today=today,
        yesterday_start=y0,
        yesterday_end=y1,
    )

    ctx.state = (
        await db.execute(
            select(SystemStateSnapshot).order_by(SystemStateSnapshot.created_at.desc()).limit(1)
        )
    ).scalar_one_or_none()

    ctx.risk = (
        await db.execute(
            select(RiskExposureSnapshot).order_by(RiskExposureSnapshot.created_at.desc()).limit(1)
        )
    ).scalar_one_or_none()

    ctx.infra = (
        await db.execute(select(InfraHealthLog).order_by(InfraHealthLog.created_at.desc()).limit(1))
    ).scalar_one_or_none()

    ctx.perf_today = (
        await db.execute(select(PerformanceDaily).where(PerformanceDaily.report_date == today))
    ).scalar_one_or_none()

    ctx.perf_yesterday = (
        await db.execute(
            select(PerformanceDaily).where(PerformanceDaily.report_date == today - timedelta(days=1))
        )
    ).scalar_one_or_none()

    ctx.alerts_open = list(
        (
            await db.execute(
                select(Alert)
                .where(Alert.acknowledged == False)  # noqa: E712
                .order_by(Alert.created_at.desc())
                .limit(30)
            )
        ).scalars().all()
    )
    ctx.alerts_critical = [a for a in ctx.alerts_open if str(a.severity) in ("critical", "emergency")]

    ctx.research_pending = list(
        (
            await db.execute(
                select(ResearchReviewQueue)
                .where(ResearchReviewQueue.status == ReviewStatus.pending)
                .order_by(ResearchReviewQueue.created_at.desc())
                .limit(15)
            )
        ).scalars().all()
    )

    ctx.marketing_drafts = list(
        (
            await db.execute(
                select(MarketingContentQueue)
                .where(MarketingContentQueue.status == "draft")
                .order_by(MarketingContentQueue.created_at.desc())
                .limit(20)
            )
        ).scalars().all()
    )

    ctx.marketing_approved = (
        await db.execute(
            select(func.count(MarketingContentQueue.id)).where(
                MarketingContentQueue.status == "approved"
            )
        )
    ).scalar() or 0

    ctx.marketing_cycle_today = (
        await db.execute(
            select(MarketingCycleReport).where(MarketingCycleReport.cycle_date == today)
        )
    ).scalar_one_or_none()

    async def _trades_between(start: datetime, end: datetime) -> list[TradeEvent]:
        r = await db.execute(
            select(TradeEvent)
            .where(and_(TradeEvent.created_at >= start, TradeEvent.created_at < end))
            .order_by(TradeEvent.created_at.desc())
        )
        return list(r.scalars().all())

    ctx.trades_yesterday = await _trades_between(y0, y1)
    ctx.trades_today = await _trades_between(t0, t1)
    ctx.open_trades = list(
        (
            await db.execute(
                select(TradeEvent).where(TradeEvent.outcome == "open").order_by(TradeEvent.created_at.desc())
            )
        ).scalars().all()
    )

    ctx.audits_yesterday = list(
        (
            await db.execute(
                select(AuditTrail)
                .where(
                    and_(AuditTrail.created_at >= y0, AuditTrail.created_at < y1)
                )
                .order_by(AuditTrail.created_at.desc())
                .limit(50)
            )
        ).scalars().all()
    )

    cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
    ctx.execution_logs_24h = list(
        (
            await db.execute(
                select(ExecutionQualityLog)
                .where(ExecutionQualityLog.created_at >= cutoff)
                .order_by(ExecutionQualityLog.created_at.desc())
            )
        ).scalars().all()
    )

    try:
        from app.agents.infra_resilience import InfrastructureResilienceAgent

        infra_agent = InfrastructureResilienceAgent(db)
        ctx.infra_live = await infra_agent.check_all_systems()
    except Exception:
        ctx.infra_live = None

    return ctx
