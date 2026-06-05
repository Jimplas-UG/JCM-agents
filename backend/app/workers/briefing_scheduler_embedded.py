"""Embedded 09:00 briefing scheduler inside JCMAPI (LocalSystem NSSM — always on)."""

from __future__ import annotations

import asyncio
from datetime import date, datetime
from zoneinfo import ZoneInfo

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.config import get_settings
from app.logging_config import get_logger
from app.workers.daily_briefing_delivery import (
    deliver_executive_briefing,
    get_delivery_record,
)

logger = get_logger("briefing_scheduler_embedded")
_scheduler: AsyncIOScheduler | None = None
_started = False


async def _run_primary() -> None:
    logger.info("embedded_briefing_primary_start")
    outcome = await deliver_executive_briefing(force=True)
    logger.info("embedded_briefing_primary_done", **outcome)


async def _run_backup() -> None:
    logger.info("embedded_briefing_backup_start")
    outcome = await deliver_executive_briefing(ensure=True)
    logger.info("embedded_briefing_backup_done", **outcome)


async def _startup_catchup() -> None:
    settings = get_settings()
    tz = ZoneInfo(settings.executive_briefing_timezone)
    now = datetime.now(tz)
    if now.hour < settings.executive_briefing_hour:
        return
    today = date.today()
    existing = await get_delivery_record(today)
    if existing and existing.get("sent"):
        logger.info("embedded_briefing_catchup_skip", date=str(today))
        return
    logger.info("embedded_briefing_catchup_start", date=str(today))
    outcome = await deliver_executive_briefing(ensure=True)
    logger.info("embedded_briefing_catchup_done", **outcome)


async def start_embedded_briefing_scheduler() -> None:
    global _scheduler, _started
    if _started:
        return
    settings = get_settings()
    tz = ZoneInfo(settings.executive_briefing_timezone)
    _scheduler = AsyncIOScheduler(timezone=tz)
    _scheduler.add_job(
        _run_primary,
        CronTrigger(
            hour=settings.executive_briefing_hour,
            minute=settings.executive_briefing_minute,
            timezone=tz,
        ),
        id="embedded_daily_briefing",
        replace_existing=True,
    )
    _scheduler.add_job(
        _run_backup,
        CronTrigger(hour=settings.executive_briefing_hour, minute=15, timezone=tz),
        id="embedded_briefing_backup",
        replace_existing=True,
    )
    _scheduler.start()
    _started = True
    logger.info(
        "embedded_briefing_scheduler_started",
        time=f"{settings.executive_briefing_hour:02d}:{settings.executive_briefing_minute:02d}",
        timezone=settings.executive_briefing_timezone,
    )
    await asyncio.sleep(2)
    await _startup_catchup()


async def stop_embedded_briefing_scheduler() -> None:
    global _scheduler, _started
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
    _started = False
