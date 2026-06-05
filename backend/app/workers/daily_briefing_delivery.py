"""
Daily executive briefing delivery — single code path for scheduler + Windows tasks.

Idempotent Telegram send per calendar day (Redis marker). Retries + failure alert.
"""

from __future__ import annotations

import asyncio
import json
from datetime import date, datetime, timezone
from typing import Any

from app.config import get_settings
from app.db.redis_client import cache_get, cache_set, close_redis
from app.db.session import AsyncSessionLocal
from app.logging_config import get_logger, setup_logging
from app.services.alerting import send_telegram_message
from app.services.executive_briefing.telegram import format_executive_briefing_telegram
from app.services.agent_registry import agent_schedule

setup_logging()
logger = get_logger("daily_briefing_delivery")

DELIVERY_KEY_PREFIX = "jcm:briefing_telegram_sent"
DELIVERY_TTL_SECONDS = 172800  # 48h
TELEGRAM_MAX_ATTEMPTS = 3


def _delivery_key(day: date) -> str:
    return f"{DELIVERY_KEY_PREFIX}:{day.isoformat()}"


async def get_delivery_record(day: date | None = None) -> dict[str, Any] | None:
    return await _load_delivery_record(day or date.today())


async def _load_delivery_record(day: date) -> dict[str, Any] | None:
    raw = await cache_get(_delivery_key(day))
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {"sent": True, "raw": raw}


async def _mark_delivery_sent(day: date, meta: dict[str, Any]) -> None:
    payload = {
        "sent": True,
        "at": datetime.now(timezone.utc).isoformat(),
        **meta,
    }
    await cache_set(_delivery_key(day), json.dumps(payload), ttl=DELIVERY_TTL_SECONDS)


async def _send_telegram_with_retries(text: str) -> bool:
    for attempt in range(1, TELEGRAM_MAX_ATTEMPTS + 1):
        if await send_telegram_message(text):
            return True
        if attempt < TELEGRAM_MAX_ATTEMPTS:
            await asyncio.sleep(2 * attempt)
    # Last resort: plain text (no Markdown)
    return await send_telegram_message(text, parse_mode=None)


async def _notify_failure(reason: str, day: date) -> None:
    settings = get_settings()
    if not settings.telegram_bot_token or not settings.telegram_chat_id:
        return
    await send_telegram_message(
        f"JCM ALERT: Executive briefing for {day} was NOT delivered.\nReason: {reason}\n"
        f"Check C:\\logs\\jcm\\daily-briefing-telegram.log on VPS.",
        parse_mode=None,
    )


async def run_agent_cycles_before_briefing() -> None:
    from app.workers.agent_scheduler import run_agent_cycle

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
    classes = {name: cls for name, (cls, _) in agent_schedule().items()}
    for name in order:
        await run_agent_cycle(name, classes[name])


async def deliver_executive_briefing(
    *,
    force: bool = False,
    ensure: bool = False,
    run_agents_before: bool | None = None,
) -> dict[str, Any]:
    """
    Build briefing, send Telegram, record delivery.

    - force: regenerate briefing and send even if already sent today
    - ensure: only deliver if not yet sent today (for backup watchdog)
    """
    settings = get_settings()
    today = date.today()
    result: dict[str, Any] = {
        "briefing_date": str(today),
        "force": force,
        "ensure": ensure,
        "telegram_sent": False,
        "status": "pending",
    }

    if not settings.telegram_bot_token or not settings.telegram_chat_id:
        result["status"] = "telegram_config_missing"
        logger.error("briefing_delivery_config_missing")
        await _notify_failure("telegram_config_missing", today)
        return result

    existing = await _load_delivery_record(today)
    if existing and existing.get("sent") and not force:
        result["status"] = "already_sent"
        result["telegram_sent"] = True
        result["sent_at"] = existing.get("at")
        logger.info("briefing_delivery_skip_already_sent", date=str(today))
        return result

    if ensure and existing and existing.get("sent"):
        result["status"] = "already_sent"
        result["telegram_sent"] = True
        return result

    should_run_agents = (
        run_agents_before
        if run_agents_before is not None
        else settings.executive_briefing_run_agents_before
    )

    try:
        if should_run_agents:
            logger.info("briefing_delivery_agents_start")
            await run_agent_cycles_before_briefing()

        from app.agents.ceo_copilot.agent import CeoCopilotAgent

        async with AsyncSessionLocal() as db:
            copilot = CeoCopilotAgent(db)
            briefing = await copilot.generate_daily_briefing(force=True)
            await db.commit()

        result["mission_status"] = briefing.get("mission_status")
        base = (settings.mission_control_public_url or "").rstrip("/")
        mc_url = f"{base}/mission-control" if base else ""
        text = format_executive_briefing_telegram(
            briefing,
            ceo_name=settings.executive_briefing_ceo_name,
            mission_control_url=mc_url,
        )

        if not settings.executive_briefing_telegram_notify:
            result["status"] = "telegram_notify_disabled"
            logger.warning("briefing_delivery_notify_disabled")
            return result

        sent = await _send_telegram_with_retries(text)
        result["telegram_sent"] = sent
        if sent:
            await _mark_delivery_sent(
                today,
                {
                    "mission_status": briefing.get("mission_status"),
                    "briefing_date": str(today),
                },
            )
            result["status"] = "sent"
            logger.info(
                "briefing_delivery_success",
                date=str(today),
                mission_status=briefing.get("mission_status"),
            )
        else:
            result["status"] = "telegram_api_failed"
            logger.error("briefing_delivery_telegram_failed", date=str(today))
            await _notify_failure("telegram_api_failed", today)
    except Exception as exc:
        result["status"] = "error"
        result["error"] = str(exc)
        logger.exception("briefing_delivery_failed", error=str(exc))
        await _notify_failure(str(exc)[:200], today)

    return result


async def deliver_executive_briefing_shutdown() -> dict[str, Any]:
    try:
        return await deliver_executive_briefing(force=False, ensure=False)
    finally:
        await close_redis()
