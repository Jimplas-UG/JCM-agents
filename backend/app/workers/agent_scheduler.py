"""Background agent scheduler — runs supervisory agent cycles."""

import asyncio
import os
import sys

from apscheduler.schedulers.asyncio import AsyncIOScheduler

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

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
from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.logging_config import get_logger, setup_logging
from app.metrics.prometheus import AGENT_CYCLE_DURATION

setup_logging()
logger = get_logger("agent_scheduler")
settings = get_settings()

AGENT_SCHEDULE = {
    "infra_resilience": (InfrastructureResilienceAgent, 30),
    "portfolio_risk": (PortfolioRiskOrchestrator, 60),
    "execution_quality": (ExecutionQualityAgent, 120),
    "performance_intel": (PerformanceIntelligenceAgent, 3600),
    "research_evolution": (ResearchEvolutionAgent, 7200),
    "ceo_copilot": (CeoCopilotAgent, 300),
    "quant_memory": (QuantMemoryAgent, 300),
    "explainability": (ExplainabilityAgent, 600),
    "marketing_agent": (MarketingAgent, 86400),
}


async def run_agent_cycle(name: str, agent_cls: type) -> None:
    import time

    start = time.perf_counter()
    async with AsyncSessionLocal() as db:
        try:
            agent = agent_cls(db)
            result = await agent.run_cycle()
            await db.commit()
            duration = time.perf_counter() - start
            AGENT_CYCLE_DURATION.labels(agent=name).observe(duration)
            logger.info("agent_cycle_complete", agent=name, result=result, duration_s=duration)
        except Exception as exc:
            await db.rollback()
            logger.error("agent_cycle_failed", agent=name, error=str(exc))


def main() -> None:
    scheduler = AsyncIOScheduler()

    for name, (agent_cls, interval_seconds) in AGENT_SCHEDULE.items():
        scheduler.add_job(
            run_agent_cycle,
            "interval",
            seconds=interval_seconds,
            args=[name, agent_cls],
            id=name,
            replace_existing=True,
        )

    scheduler.start()
    logger.info("agent_scheduler_started", agents=list(AGENT_SCHEDULE.keys()))

    try:
        asyncio.get_event_loop().run_forever()
    except (KeyboardInterrupt, SystemExit):
        scheduler.shutdown()


if __name__ == "__main__":
    main()
