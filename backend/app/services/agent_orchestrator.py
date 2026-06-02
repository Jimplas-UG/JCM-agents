"""Cross-agent coordination — priorities, health, conflict guard (not a 10th agent)."""

from __future__ import annotations

import json
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Literal

from app.db.redis_client import CHANNEL_AGENT_BUS, cache_get, cache_set, publish
from app.metrics.prometheus import update_operational_gauges
from app.services.agent_guard import (
    assert_allowed_action,
    assert_allowed_agent,
    validate_agent_result,
)

Priority = Literal["critical", "high", "medium", "low"]

_last_cycle: dict[str, dict[str, Any]] = {}
_remediation_times: list[float] = []
_alert_dedup: dict[str, float] = {}
ACTION_AUDIT_KEY = "jcm:action_audit"
ACTION_AUDIT_MAX = 500
MAX_REMEDIATIONS_PER_HOUR = 8
ALERT_DEDUP_SECONDS = 300


def record_agent_cycle(
    agent: str,
    *,
    success: bool,
    duration_s: float,
    result: dict[str, Any] | None = None,
) -> None:
    validation = validate_agent_result(agent, result if success else None)
    if validation.get("issues"):
        log_action_sync(agent, "output_validation_warning", validation, priority="high")

    interval = result.get("interval_seconds") if result else None
    health = _health_score(success, duration_s, interval)
    if validation.get("issues"):
        health = min(health, 40)

    _last_cycle[agent] = {
        "agent": agent,
        "success": success,
        "duration_s": round(duration_s, 3),
        "health_score": health,
        "last_run_at": datetime.now(timezone.utc).isoformat(),
        "result_status": (result or {}).get("status"),
        "validation": validation,
    }
    if success and result:
        update_operational_gauges(result)


async def log_action(
    agent: str,
    action: str,
    payload: dict[str, Any],
    *,
    priority: Priority = "medium",
) -> None:
    if not assert_allowed_agent(agent) or not assert_allowed_action(action):
        return
    entry = {
        "id": str(uuid.uuid4()),
        "agent": agent,
        "action": action,
        "priority": priority,
        "payload": payload,
        "at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        raw = await cache_get(ACTION_AUDIT_KEY)
        items = json.loads(raw) if raw else []
        if not isinstance(items, list):
            items = []
        items.insert(0, entry)
        items = items[:ACTION_AUDIT_MAX]
        await cache_set(ACTION_AUDIT_KEY, json.dumps(items, default=str), ttl=86400 * 7)
    except Exception:
        pass


def log_action_sync(agent: str, action: str, payload: dict[str, Any], **kwargs: Any) -> None:
    """Fire-and-forget audit from sync contexts."""
    import asyncio

    try:
        loop = asyncio.get_running_loop()
        loop.create_task(log_action(agent, action, payload, **kwargs))
    except RuntimeError:
        pass


async def get_action_audit(limit: int = 100) -> list[dict[str, Any]]:
    try:
        raw = await cache_get(ACTION_AUDIT_KEY)
        if not raw:
            return []
        items = json.loads(raw)
        return items[:limit] if isinstance(items, list) else []
    except Exception:
        return []


async def publish_agent_message(
    source_agent: str,
    action: str,
    payload: dict[str, Any],
    *,
    priority: Priority = "medium",
    target: str = "all",
    ttl_seconds: int = 300,
) -> None:
    if not assert_allowed_agent(source_agent) or not assert_allowed_action(action):
        return
    if action == "remediation_requested" and not _allow_remediation():
        await log_action(source_agent, "remediation_blocked_rate_limit", payload, priority="high")
        return
    if action == "alert_raise" and not _allow_alert(payload.get("title", "")):
        return

    await log_action(source_agent, action, payload, priority=priority)
    envelope = {
        "id": str(uuid.uuid4()),
        "priority": priority,
        "source_agent": source_agent,
        "target": target,
        "action": action,
        "payload": payload,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "ttl_seconds": ttl_seconds,
    }
    await publish(CHANNEL_AGENT_BUS, json.dumps(envelope, default=str))


def reserve_remediation_slot() -> bool:
    """Return True if infra may attempt watchdog/MT5 remediation (rate-limited)."""
    return _allow_remediation()


def _allow_remediation() -> bool:
    now = time.time()
    global _remediation_times
    _remediation_times = [t for t in _remediation_times if now - t < 3600]
    if len(_remediation_times) >= MAX_REMEDIATIONS_PER_HOUR:
        return False
    _remediation_times.append(now)
    return True


def _allow_alert(title: str) -> bool:
    key = str(title)[:120]
    now = time.time()
    last = _alert_dedup.get(key, 0)
    if now - last < ALERT_DEDUP_SECONDS:
        return False
    _alert_dedup[key] = now
    return True


def _health_score(success: bool, duration_s: float, interval_seconds: int | None) -> int:
    if not success:
        return 0
    score = 100
    if interval_seconds and duration_s > interval_seconds * 0.8:
        score -= 25
    if duration_s > 30:
        score -= 15
    return max(0, min(100, score))


def get_agents_health() -> dict[str, Any]:
    schedule = {}
    try:
        from app.services.agent_registry import agent_schedule

        schedule = {k: v[1] for k, v in agent_schedule().items()}
    except Exception:
        pass

    agents = []
    for name, interval in schedule.items():
        rec = _last_cycle.get(name, {})
        agents.append(
            {
                "name": name,
                "interval_seconds": interval,
                "health_score": rec.get("health_score", 50 if rec else None),
                "last_run_at": rec.get("last_run_at"),
                "last_success": rec.get("success"),
                "duration_s": rec.get("duration_s"),
                "validation_issues": (rec.get("validation") or {}).get("issues", []),
                "status": "healthy" if rec.get("health_score", 0) >= 70 else (
                    "degraded" if rec.get("health_score") is not None else "unknown"
                ),
            }
        )
    return {
        "agents": agents,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
