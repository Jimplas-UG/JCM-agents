"""Background agent scheduler — runs supervisory agent cycles."""

import asyncio
import os
import sys
import time

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(__file__))))

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.logging_config import get_logger, setup_logging
from app.metrics.prometheus import AGENT_CYCLE_DURATION
from app.services.agent_orchestrator import record_agent_cycle
from app.services.agent_registry import INGEST_DRIVEN_AGENTS, agent_schedule
from app.workers.daily_briefing_delivery import deliver_executive_briefing

setup_logging()
logger = get_logger("agent_scheduler")
settings = get_settings()

_AGENT_CLASSES = {name: cls for name, (cls, _) in agent_schedule().items()}

_ingest_activity: dict[str, float] = {}


def mark_ingest_activity(agent: str) -> None:
    _ingest_activity[agent] = time.time()


async def run_agent_cycle(name: str, agent_cls: type) -> None:
    if name in INGEST_DRIVEN_AGENTS:
        last = _ingest_activity.get(name, 0)
        if time.time() - last > 600:
            logger.debug("agent_cycle_skipped_idle", agent=name)
            return

    start = time.perf_counter()
    async with AsyncSessionLocal() as db:
        try:
            agent = agent_cls(db)
            result = await agent.run_cycle()
            await db.commit()
            duration = time.perf_counter() - start
            AGENT_CYCLE_DURATION.labels(agent=name).observe(duration)
            interval = agent_schedule().get(name, (None, 0))[1]
            enriched = dict(result or {})
            enriched["interval_seconds"] = interval
            record_agent_cycle(name, success=True, duration_s=duration, result=enriched)
            logger.info("agent_cycle_complete", agent=name, result=result, duration_s=duration)
        except Exception as exc:
            await db.rollback()
            duration = time.perf_counter() - start
            record_agent_cycle(name, success=False, duration_s=duration)
            logger.error("agent_cycle_failed", agent=name, error=str(exc))


async def run_daily_executive_briefing() -> None:
    """09:00 Kampala — shared delivery pipeline (same as Windows scheduled task)."""
    logger.info(
        "daily_executive_briefing_start",
        timezone=settings.executive_briefing_timezone,
        hour=settings.executive_briefing_hour,
    )
    outcome = await deliver_executive_briefing(force=True)
    if outcome.get("telegram_sent") or outcome.get("status") == "already_sent":
        logger.info("daily_executive_briefing_complete", **outcome)
    else:
        logger.error("daily_executive_briefing_failed", **outcome)


async def _run_scheduler() -> None:
    scheduler = AsyncIOScheduler()

    for name, (agent_cls, interval_seconds) in agent_schedule().items():
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
        agents=list(agent_schedule().keys()),
        executive_briefing=f"{settings.executive_briefing_hour:02d}:{settings.executive_briefing_minute:02d} {settings.executive_briefing_timezone}",
    )
    try:
        await asyncio.Event().wait()
    finally:
        scheduler.shutdown(wait=False)


def main() -> None:
    try:
        asyncio.run(_run_scheduler())
    except (KeyboardInterrupt, SystemExit):
        pass


if __name__ == "__main__":
    main()
