"""Health check and agent status endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents import (
    CeoCopilotAgent,
    ExecutionQualityAgent,
    ExplainabilityAgent,
    InfrastructureResilienceAgent,
    MarketingAgent,
    PerformanceIntelligenceAgent,
    PortfolioRiskOrchestrator,
    QuantMemoryAgent,
    ResearchEvolutionAgent,
)
from app.api.deps import get_db_session, verify_api_key
from app.config import get_settings
from app.db.redis_client import get_redis

router = APIRouter(tags=["health"])

AGENTS = {
    "quant_memory": QuantMemoryAgent,
    "performance_intel": PerformanceIntelligenceAgent,
    "infra_resilience": InfrastructureResilienceAgent,
    "portfolio_risk": PortfolioRiskOrchestrator,
    "execution_quality": ExecutionQualityAgent,
    "explainability": ExplainabilityAgent,
    "research_evolution": ResearchEvolutionAgent,
    "ceo_copilot": CeoCopilotAgent,
    "marketing_agent": MarketingAgent,
}

AGENT_DESCRIPTIONS = {
    "quant_memory": "Records BSv3.2 trade events and system snapshots",
    "performance_intel": "Win rate, expectancy, edge decay analytics",
    "infra_resilience": "VPS/API health monitoring and remediation",
    "portfolio_risk": "Exposure, correlation, drawdown assessment",
    "execution_quality": "Slippage, spread, fill speed metrics",
    "explainability": "Structured audit trail for BSv3.2 decisions",
    "research_evolution": "Drift detection and human review queue",
    "ceo_copilot": "Executive briefing and dashboard overview",
    "marketing_agent": "Brand content drafts and trend signals",
}


@router.get("/health")
async def health_check(db: AsyncSession = Depends(get_db_session)) -> dict:
    db_ok = False
    redis_ok = False
    db_error: str | None = None
    redis_error: str | None = None
    try:
        await db.execute(text("SELECT 1"))
        db_ok = True
    except Exception as exc:
        db_error = str(exc)
    try:
        r = await get_redis()
        redis_ok = await r.ping()
    except Exception as exc:
        redis_error = str(exc)

    settings = get_settings()
    status = "healthy" if db_ok and redis_ok else "degraded"
    result: dict = {
        "status": status,
        "database": "ok" if db_ok else "error",
        "redis": "ok" if redis_ok else "error",
        "bsv32_engine": "read-only-observer",
        "registered_agents": len(AGENTS),
    }
    if settings.bsv32_home:
        result["bsv32_home"] = settings.bsv32_home
    if db_error:
        result["database_error"] = db_error
    if redis_error:
        result["redis_error"] = redis_error
    return result


AGENT_INTERVALS = {
    "infra_resilience": 30,
    "portfolio_risk": 60,
    "execution_quality": 120,
    "performance_intel": 3600,
    "research_evolution": 7200,
    "ceo_copilot": 300,
    "quant_memory": 300,
    "explainability": 600,
    "marketing_agent": 86400,
}


@router.get("/agents/registry")
async def agents_registry() -> dict:
    """List all 9 supervisory agents and their schedule (read-only, no cycle execution)."""
    agents = []
    for name, agent_cls in AGENTS.items():
        interval = AGENT_INTERVALS.get(name, 0)
        agents.append(
            {
                "name": name,
                "class": agent_cls.__name__,
                "description": getattr(agent_cls, "description", ""),
                "interval_seconds": interval,
                "interval_label": _format_interval(interval),
            }
        )
    return {"count": len(agents), "agents": agents, "mode": "read-only-observer"}


def _format_interval(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h"


@router.get("/agents/status")
async def agents_status() -> dict:
    """Read-only registry — does not execute agent cycles (avoids side effects)."""
    return {
        "agents": {
            name: {
                "status": "registered",
                "description": AGENT_DESCRIPTIONS.get(name, ""),
                "class": agent_cls.__name__,
            }
            for name, agent_cls in AGENTS.items()
        }
    }


@router.post("/agents/{agent_name}/run", dependencies=[Depends(verify_api_key)])
async def run_agent(
    agent_name: str,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    agent_cls = AGENTS.get(agent_name)
    if not agent_cls:
        raise HTTPException(status_code=404, detail=f"Unknown agent: {agent_name}")
    agent = agent_cls(db)
    result = await agent.run_cycle()
    return {"agent": agent_name, **result}
