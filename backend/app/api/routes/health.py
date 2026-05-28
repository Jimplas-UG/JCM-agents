"""Health check and agent status endpoints."""

from fastapi import APIRouter, Depends
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
from app.api.deps import get_db_session
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


@router.get("/health")
async def health_check(db: AsyncSession = Depends(get_db_session)) -> dict:
    db_ok = False
    redis_ok = False
    try:
        await db.execute(text("SELECT 1"))
        db_ok = True
    except Exception:
        pass
    try:
        r = await get_redis()
        redis_ok = await r.ping()
    except Exception:
        pass

    status = "healthy" if db_ok and redis_ok else "degraded"
    return {
        "status": status,
        "database": "ok" if db_ok else "error",
        "redis": "ok" if redis_ok else "error",
        "bsv32_engine": "read-only-observer",
    }


@router.get("/agents/status")
async def agents_status(db: AsyncSession = Depends(get_db_session)) -> dict:
    results = {}
    for name, agent_cls in AGENTS.items():
        agent = agent_cls(db)
        try:
            result = await agent.run_cycle()
            results[name] = {"status": "ok", **result}
        except Exception as exc:
            results[name] = {"status": "error", "error": str(exc)}
    return {"agents": results}


@router.post("/agents/{agent_name}/run")
async def run_agent(
    agent_name: str,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    agent_cls = AGENTS.get(agent_name)
    if not agent_cls:
        return {"status": "error", "message": f"Unknown agent: {agent_name}"}
    agent = agent_cls(db)
    result = await agent.run_cycle()
    return {"agent": agent_name, **result}
