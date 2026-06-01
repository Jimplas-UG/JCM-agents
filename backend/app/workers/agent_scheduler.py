"""Background agent scheduler — runs supervisory agent cycles."""

import asyncio
import os
import sys

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from zoneinfo import ZoneInfo

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

_AGENT_CLASSES = {
    "infra_resilience": InfrastructureResilienceAgent,
    "portfolio_risk": PortfolioRiskOrchestrator,
    "execution_quality": ExecutionQualityAgent,
    "performance_intel": PerformanceIntelligenceAgent,
    "research_evolution": ResearchEvolutionAgent,
    "quant_memory": QuantMemoryAgent,
    "explainability": ExplainabilityAgent,
    "marketing_agent": MarketingAgent,
    "ceo_copilot": CeoCopilotAgent,
}


def _agent_schedule() -> dict:
    marketing_interval = max(3600, settings.marketing_cycle_hours * 3600)
    return {
        "infra_resilience": (InfrastructureResilienceAgent, 30),
        "portfolio_risk": (PortfolioRiskOrchestrator, 60),
        "execution_quality": (ExecutionQualityAgent, 120),
        "performance_intel": (PerformanceIntelligenceAgent, 3600),
        "research_evolution": (ResearchEvolutionAgent, 7200),
        "ceo_copilot": (CeoCopilotAgent, 300),
        "quant_memory": (QuantMemoryAgent, 300),
        "explainability": (ExplainabilityAgent, 600),
        "marketing_agent": (MarketingAgent, marketing_interval),
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


async def run_daily_executive_briefing() -> None:
    """09:00 local — all 9 agents refresh data, then CEO executive briefing is published."""
    logger.info(
        "daily_executive_briefing_start",
        timezone=settings.executive_briefing_timezone,
        hour=settings.executive_briefing_hour,
    )

    if settings.executive_briefing_run_agents_before:
        order = [
            "infra_resilience",
            "quant_memory",
            "portfolio_risk",
            "execution_quality",
            "performance_intel",
            "explainability",
            "research_evolution",
            "marketing_agent",
        ]
        for name in order:
            await run_agent_cycle(name, _AGENT_CLASSES[name])

    async with AsyncSessionLocal() as db:
        try:
            copilot = CeoCopilotAgent(db)
            result = await copilot.generate_daily_briefing()
            await db.commit()
            logger.info("daily_executive_briefing_complete", **result)
        except Exception as exc:
            await db.rollback()
            logger.error("daily_executive_briefing_failed", error=str(exc))


def main() -> None:
    scheduler = AsyncIOScheduler()

    for name, (agent_cls, interval_seconds) in _agent_schedule().items():
        scheduler.add_job(
            run_agent_cycle,
            "interval",
            seconds=interval_seconds,
            args=[name, agent_cls],
            id=name,
            replace_existing=True,
        )

    tz = ZoneInfo(settings.executive_briefing_timezone)
    scheduler.add_job(
        run_daily_executive_briefing,
        CronTrigger(
            hour=settings.executive_briefing_hour,
            minute=settings.executive_briefing_minute,
            timezone=tz,
        ),
        id="daily_executive_briefing",
        replace_existing=True,
    )

    scheduler.start()
    logger.info(
        "agent_scheduler_started",
        agents=list(_agent_schedule().keys()),
        executive_briefing=f"{settings.executive_briefing_hour:02d}:{settings.executive_briefing_minute:02d} {settings.executive_briefing_timezone}",
    )

    try:
        asyncio.get_event_loop().run_forever()
    except (KeyboardInterrupt, SystemExit):
        scheduler.shutdown()


if __name__ == "__main__":
    main()
