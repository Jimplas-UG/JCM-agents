"""Health check and agent status endpoints."""

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_db_session, verify_api_key, verify_mission_control_or_api_key
from app.config import get_settings
from app.db.redis_client import get_redis
from app.models.tables import Alert
from app.services.agent_orchestrator import get_agents_health
from app.services.agent_registry import AGENT_CLASSES, AGENT_DESCRIPTIONS, agent_schedule, format_interval

router = APIRouter(tags=["health"])


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
        "registered_agents": len(AGENT_CLASSES),
        "platform": "institutional-v2",
    }
    if settings.bsv32_home:
        result["bsv32_home"] = settings.bsv32_home
    if db_error:
        result["database_error"] = db_error
    if redis_error:
        result["redis_error"] = redis_error

    try:
        alert_r = await db.execute(
            select(func.count()).select_from(Alert).where(Alert.acknowledged.is_(False))
        )
        from app.metrics.prometheus import ACTIVE_ALERTS

        ACTIVE_ALERTS.labels(severity="all").set(int(alert_r.scalar() or 0))
    except Exception:
        pass

    return result


@router.get("/agents/registry", dependencies=[Depends(verify_mission_control_or_api_key)])
async def agents_registry() -> dict:
    schedule = agent_schedule()
    agents = []
    for name, (agent_cls, interval) in schedule.items():
        agents.append(
            {
                "name": name,
                "class": agent_cls.__name__,
                "description": AGENT_DESCRIPTIONS.get(name, getattr(agent_cls, "description", "")),
                "interval_seconds": interval,
                "interval_label": format_interval(interval),
            }
        )
    return {"count": len(agents), "agents": agents, "mode": "read-only-observer"}


@router.get("/agents/health", dependencies=[Depends(verify_mission_control_or_api_key)])
async def agents_health() -> dict:
    """Per-agent health scores from last scheduler cycles."""
    return get_agents_health()


@router.get("/agents/status")
async def agents_status() -> dict:
    return {
        "agents": {
            name: {
                "status": "registered",
                "description": AGENT_DESCRIPTIONS.get(name, ""),
                "class": agent_cls.__name__,
            }
            for name, agent_cls in AGENT_CLASSES.items()
        }
    }


@router.post("/agents/{agent_name}/run", dependencies=[Depends(verify_api_key)])
async def run_agent(
    agent_name: str,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    agent_cls = AGENT_CLASSES.get(agent_name)
    if not agent_cls:
        raise HTTPException(status_code=404, detail=f"Unknown agent: {agent_name}")
    agent = agent_cls(db)
    result = await agent.run_cycle()
    return {"agent": agent_name, **(result or {})}
