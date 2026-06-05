"""Allocator due-diligence gates — what an LP needs before writing a check."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.tables import TradeEvent, TradeOutcome
from app.services.execution_halt import halt_status


def _allocator_json_paths() -> list[Path]:
    return [
        Path(r"C:\opt\bilshenz\backend\validation\data\allocator-readiness.json"),
        Path(__file__).resolve().parents[3]
        / "infra"
        / "bilshenz"
        / "validation"
        / "data"
        / "allocator-readiness.json",
    ]


def _research_reports() -> list[Path]:
    data = Path(r"C:\opt\bilshenz\backend\validation\data")
    if not data.is_dir():
        return []
    return sorted(data.glob("*realistic-mt5*output.txt"), key=lambda p: p.stat().st_mtime, reverse=True)


def _parse_research(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8", errors="replace")
    pf = re.search(r"Profit factor[^:]*:\s*([\d.]+)", text, re.I)
    trades = re.search(r"Closed in window:\s*(\d+)", text)
    wr = re.search(r"Win rate \(closed\):\s*([\d.]+)%", text)
    return {
        "path": str(path),
        "profit_factor": float(pf.group(1)) if pf else None,
        "trades": int(trades.group(1)) if trades else None,
        "win_rate_pct": float(wr.group(1)) if wr else None,
        "ok": (float(pf.group(1)) >= 1.5 if pf else False)
        and (int(trades.group(1)) >= 100 if trades else False),
    }


async def count_stale_jcm_opens(db: AsyncSession) -> int:
    """Open JCM rows with no matching MT5 position (allocator blocker)."""
    result = await db.execute(
        select(TradeEvent).where(TradeEvent.outcome == TradeOutcome.open)
    )
    return len(list(result.scalars().all()))


async def build_allocator_readiness_payload(db: AsyncSession) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "check_ready": False,
        "progress_score": 0,
        "tier": "not_ready",
        "gates": [],
        "blockers": [],
        "next_milestones": [],
        "stale_jcm_opens": await count_stale_jcm_opens(db),
        "halt": halt_status(),
        "research": None,
        "jcm_trades": {},
        "source": "computed",
    }

    for path in _allocator_json_paths():
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            rep = data.get("report", {})
            gates = rep.get("gates", [])
            payload.update(
                {
                    "check_ready": rep.get("checkReady", False),
                    "progress_score": rep.get("progressScore", 0),
                    "tier": rep.get("tier", "not_ready"),
                    "gates": gates,
                    "gates_passed": sum(1 for g in gates if g.get("pass")),
                    "gates_total": len(gates) or 9,
                    "blockers": rep.get("blockers", []),
                    "next_milestones": rep.get("nextMilestones", []),
                    "research": data.get("research"),
                    "tca": data.get("tca"),
                    "live_metrics": data.get("live"),
                    "source": "bilshenz_report",
                }
            )
            break
        except (json.JSONDecodeError, OSError):
            continue

    reports = _research_reports()
    if reports and not payload.get("research"):
        payload["research"] = _parse_research(reports[0])

    closed_n = await db.scalar(
        select(func.count())
        .select_from(TradeEvent)
        .where(TradeEvent.outcome != TradeOutcome.open)
    )
    open_n = await db.scalar(
        select(func.count()).select_from(TradeEvent).where(TradeEvent.outcome == TradeOutcome.open)
    )
    payload["jcm_trades"] = {"open": int(open_n or 0), "closed": int(closed_n or 0)}

    if payload["source"] == "computed":
        closed = int(closed_n or 0)
        payload["progress_score"] = min(55, 20 + closed)
        payload["blockers"] = [
            "Run allocator readiness report on VPS after 90d clean forward",
            f"Live closed trades: {closed}/50 required",
        ]

    return payload
