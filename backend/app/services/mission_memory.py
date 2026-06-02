"""Mission snapshot cache — lightweight live tick without full briefing context."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.redis_client import cache_get, cache_set
from app.models.tables import InfraHealthLog, RiskExposureSnapshot, SystemStateSnapshot

SNAPSHOT_KEY = "jcm:mission_snapshot"
SNAPSHOT_TTL = 120


async def save_mission_snapshot(overview: dict[str, Any]) -> None:
    payload = {**overview, "cached_at": datetime.now(timezone.utc).isoformat()}
    await cache_set(SNAPSHOT_KEY, json.dumps(payload, default=str), ttl=SNAPSHOT_TTL)


async def load_mission_snapshot() -> dict[str, Any] | None:
    raw = await cache_get(SNAPSHOT_KEY)
    if not raw:
        return None
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return None


async def load_light_context(db: AsyncSession) -> dict[str, Any]:
    """Two-query context for live tick when Redis cache is cold."""
    state_r = await db.execute(
        select(SystemStateSnapshot).order_by(SystemStateSnapshot.created_at.desc()).limit(1)
    )
    state = state_r.scalar_one_or_none()
    risk_r = await db.execute(
        select(RiskExposureSnapshot).order_by(RiskExposureSnapshot.created_at.desc()).limit(1)
    )
    risk = risk_r.scalar_one_or_none()
    infra_r = await db.execute(
        select(InfraHealthLog).order_by(InfraHealthLog.created_at.desc()).limit(1)
    )
    infra = infra_r.scalar_one_or_none()

    market_regime = "unknown"
    if state and state.market_regime is not None:
        market_regime = (
            state.market_regime.value
            if hasattr(state.market_regime, "value")
            else str(state.market_regime)
        )

    return {
        "state": state,
        "risk": risk,
        "infra": infra,
        "market_regime": market_regime,
        "bsv32_status": state.bsv32_status if state else "unknown",
        "system_running": state.bsv32_status == "running" if state else False,
        "nfp_blackout": state.nfp_blackout if state else False,
        "risk_score": float(risk.risk_score or 0) if risk else 0,
        "infra_health_score": _infra_score(infra),
        "mt5_connected": infra.mt5_connected if infra else False,
    }


def _infra_score(infra: InfraHealthLog | None) -> float:
    if not infra:
        return 0.0
    score = 1.0
    if not infra.mt5_connected:
        score -= 0.3
    if not infra.desk_api_ok:
        score -= 0.2
    if not infra.forward_bot_ok:
        score -= 0.2
    if float(infra.vps_cpu_pct or 0) > 85:
        score -= 0.15
    if float(infra.vps_ram_pct or 0) > 85:
        score -= 0.15
    return round(max(0, score), 2)
