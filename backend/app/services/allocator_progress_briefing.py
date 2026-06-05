"""Allocator progress block for executive briefing and Mission Control."""

from __future__ import annotations

from typing import Any


def build_allocator_briefing_block(payload: dict[str, Any]) -> dict[str, Any]:
    """Normalize allocator readiness into briefing-friendly structure."""
    gates = payload.get("gates") or []
    passed = sum(1 for g in gates if g.get("pass"))
    total = len(gates) or 9
    blockers = payload.get("blockers") or payload.get("next_milestones") or []
    jcm = payload.get("jcm_trades") or {}
    research = payload.get("research") or {}

    live_closed = int(jcm.get("closed") or 0)
    return {
        "check_ready": bool(payload.get("check_ready")),
        "progress_score": int(payload.get("progress_score") or 0),
        "tier": payload.get("tier") or "not_ready",
        "gates_passed": int(payload.get("gates_passed") or passed),
        "gates_total": int(payload.get("gates_total") or total),
        "gates": gates,
        "blockers": blockers[:6],
        "next_milestones": payload.get("next_milestones") or [],
        "live_closed_trades": int(jcm.get("closed") or 0),
        "live_closed_target": 50,
        "stale_jcm_opens": int(payload.get("stale_jcm_opens") or 0),
        "research_pf": research.get("profit_factor") if isinstance(research, dict) else None,
        "research_trades": research.get("trades") if isinstance(research, dict) else None,
        "headline": _headline(payload),
        "summary_paragraph": _summary_paragraph(payload, passed, total),
    }


def _headline(payload: dict[str, Any]) -> str:
    if payload.get("check_ready"):
        return "Allocator check-ready: all due-diligence gates passed."
    score = int(payload.get("progress_score") or 0)
    tier = str(payload.get("tier") or "building").replace("_", " ")
    return f"Allocator progress {score}/100 ({tier}) — not yet check-ready."


def _summary_paragraph(payload: dict[str, Any], passed: int, total: int) -> str:
    if payload.get("check_ready"):
        return (
            "All allocator due-diligence gates are green. Tear sheet and research attestation "
            "are ready for LP conversations. Maintain discipline — do not alter strategy or risk "
            "without documented governance review."
        )
    blockers = payload.get("blockers") or []
    top = blockers[0] if blockers else "Continue clean forward execution"
    jcm = payload.get("jcm_trades") or {}
    closed = int(jcm.get("closed") or 0)
    return (
        f"Path to an institutional allocator check: {passed}/{total} gates passing today. "
        f"Live closed trades {closed}/50; primary blocker: {top}. "
        "No external capital marketing until check-ready flips YES."
    )


def allocator_executive_summary_line(block: dict[str, Any]) -> str:
    return block.get("summary_paragraph") or block.get("headline", "")
