"""Dashboard API endpoints for CEO mission control."""

from datetime import date
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.ceo_copilot import CeoCopilotAgent
from app.agents.execution_quality import ExecutionQualityAgent
from app.agents.explainability import ExplainabilityAgent
from app.agents.infra_resilience import InfrastructureResilienceAgent
from app.agents.performance_intel import PerformanceIntelligenceAgent
from app.agents.portfolio_risk import PortfolioRiskOrchestrator
from app.agents.quant_memory import QuantMemoryAgent
from app.api.deps import get_db_session
from app.models.tables import Alert, CeoBriefing, PerformanceDaily, ResearchReviewQueue, TradeEvent
from app.schemas.events import (
    AlertResponse,
    DashboardOverview,
    PerformanceReportResponse,
    ResearchFindingResponse,
    TradeEventResponse,
)

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get("/overview", response_model=DashboardOverview)
async def get_overview(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = CeoCopilotAgent(db)
    return await agent.get_dashboard_overview()


@router.get("/trades", response_model=list[TradeEventResponse])
async def get_trades(
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db_session),
) -> list:
    agent = QuantMemoryAgent(db)
    return await agent.get_recent_trades(limit)


@router.get("/risk")
async def get_risk(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = PortfolioRiskOrchestrator(db)
    snapshot = await agent.assess_risk()
    return {
        "risk_score": float(snapshot.risk_score or 0),
        "account_drawdown_pct": float(snapshot.account_drawdown_pct or 0),
        "daily_drawdown_pct": float(snapshot.daily_drawdown_pct or 0),
        "open_positions": snapshot.open_positions,
        "lot_scaling_factor": float(snapshot.lot_scaling_factor),
        "kill_switch_recommended": snapshot.kill_switch_recommended,
        "correlated_pairs": snapshot.correlated_pairs,
        "alerts": snapshot.alerts,
    }


@router.get("/infrastructure")
async def get_infrastructure(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = InfrastructureResilienceAgent(db)
    health = await agent.check_all_systems()
    latest = await agent.get_latest_health()
    return {"current": health, "latest_log_id": str(latest.id) if latest else None}


@router.get("/execution-quality")
async def get_execution_quality(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = ExecutionQualityAgent(db)
    return await agent.analyze_recent_execution()


@router.get("/performance", response_model=PerformanceReportResponse | None)
async def get_performance(
    report_date: date | None = None,
    db: AsyncSession = Depends(get_db_session),
):
    target = report_date or date.today()
    result = await db.execute(
        select(PerformanceDaily).where(PerformanceDaily.report_date == target)
    )
    return result.scalar_one_or_none()


@router.post("/performance/generate")
async def generate_performance_report(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = PerformanceIntelligenceAgent(db)
    return await agent.generate_daily_report()


@router.get("/audit")
async def get_audit_trail(
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db_session),
) -> list:
    agent = ExplainabilityAgent(db)
    audits = await agent.get_recent_audits(limit)
    return [
        {
            "id": str(a.id),
            "created_at": a.created_at.isoformat(),
            "event_type": a.event_type,
            "summary": a.summary,
            "human_readable": a.human_readable,
            "severity": a.severity,
        }
        for a in audits
    ]


@router.get("/alerts", response_model=list[AlertResponse])
async def get_alerts(
    acknowledged: bool | None = False,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db_session),
) -> list:
    query = select(Alert).order_by(Alert.created_at.desc()).limit(limit)
    if acknowledged is not None:
        query = query.where(Alert.acknowledged == acknowledged)
    result = await db.execute(query)
    return list(result.scalars().all())


@router.post("/alerts/{alert_id}/acknowledge")
async def acknowledge_alert(
    alert_id: UUID,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    result = await db.execute(select(Alert).where(Alert.id == alert_id))
    alert = result.scalar_one_or_none()
    if not alert:
        return {"status": "not_found"}
    alert.acknowledged = True
    await db.flush()
    return {"status": "acknowledged", "id": str(alert_id)}


@router.get("/research", response_model=list[ResearchFindingResponse])
async def get_research_queue(
    status: str = "pending",
    db: AsyncSession = Depends(get_db_session),
) -> list:
    result = await db.execute(
        select(ResearchReviewQueue)
        .where(ResearchReviewQueue.status == status)
        .order_by(ResearchReviewQueue.created_at.desc())
        .limit(50)
    )
    return list(result.scalars().all())


@router.post("/research/{finding_id}/review")
async def review_finding(
    finding_id: UUID,
    body: dict,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    from datetime import datetime, timezone

    result = await db.execute(
        select(ResearchReviewQueue).where(ResearchReviewQueue.id == finding_id)
    )
    finding = result.scalar_one_or_none()
    if not finding:
        return {"status": "not_found"}
    finding.status = body.get("status", "approved")
    finding.reviewed_by = body.get("reviewed_by", "ceo")
    finding.review_notes = body.get("notes", "")
    finding.updated_at = datetime.now(timezone.utc)
    await db.flush()
    return {"status": "reviewed", "id": str(finding_id)}


@router.get("/briefing")
async def get_ceo_briefing(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = CeoCopilotAgent(db)
    return await agent.generate_daily_briefing()


@router.get("/briefing/history")
async def get_briefing_history(
    limit: int = Query(7, le=30),
    db: AsyncSession = Depends(get_db_session),
) -> list:
    result = await db.execute(
        select(CeoBriefing).order_by(CeoBriefing.briefing_date.desc()).limit(limit)
    )
    rows = result.scalars().all()
    return [
        {
            "briefing_date": str(r.briefing_date),
            "system_status": r.system_status,
            "live_pnl": float(r.live_pnl or 0),
            "risk_score": float(r.risk_score or 0),
            "active_alerts": r.active_alerts_count,
        }
        for r in rows
    ]
