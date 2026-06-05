"""Load institutional readiness snapshot for Mission Control."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.tables import TradeEvent, TradeOutcome


def _readiness_json_paths() -> list[Path]:
    candidates = [
        Path(r"C:\opt\bilshenz\backend\validation\data\institutional-readiness.json"),
        Path(__file__).resolve().parents[3]
        / "infra"
        / "bilshenz"
        / "validation"
        / "data"
        / "institutional-readiness.json",
    ]
    return [p for p in candidates if p.is_file()]


async def build_institutional_readiness_payload(db: AsyncSession) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "source": "computed",
        "composite_score": None,
        "tier": "development",
        "dimensions": [],
        "jcm_trades": {},
    }

    for path in _readiness_json_paths():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            payload.update(data.get("readiness", {}))
            payload["source"] = "bilshenz_report"
            payload["live_metrics"] = data.get("live")
            payload["scores"] = data.get("scores")
            payload["reconciliation"] = data.get("reconciliation")
            payload["stress"] = data.get("stress")
            break
        except (json.JSONDecodeError, OSError):
            continue

    open_n = await db.scalar(
        select(func.count()).select_from(TradeEvent).where(TradeEvent.outcome == TradeOutcome.open)
    )
    closed_n = await db.scalar(
        select(func.count())
        .select_from(TradeEvent)
        .where(TradeEvent.outcome != TradeOutcome.open)
    )
    payload["jcm_trades"] = {"open": int(open_n or 0), "closed": int(closed_n or 0)}

    if payload.get("composite_score") is None:
        closed = int(closed_n or 0)
        payload["composite_score"] = min(72, 50 + closed * 2)
        payload["tier"] = "prop_micro" if closed >= 8 else "development"
        payload["note"] = "Run institutional readiness report on VPS for full score"

    return payload
