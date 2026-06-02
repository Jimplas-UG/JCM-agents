"""Safety guardrails for supervisory agents (read-only vs BSv3.2)."""

from __future__ import annotations

import math
import re
from typing import Any
from urllib.parse import urlparse

from app.config import get_settings
from app.logging_config import get_logger

logger = get_logger("agent_guard")

FORBIDDEN_ACTIONS = frozenset({
    "modify_strategy",
    "override_filter",
    "force_trade",
    "disable_bsv32",
    "write_strategy_config",
    "auto_deploy_strategy",
})

ALLOWED_AGENT_NAMES = frozenset({
    "infra_resilience",
    "portfolio_risk",
    "execution_quality",
    "performance_intel",
    "research_evolution",
    "quant_memory",
    "explainability",
    "marketing_agent",
    "ceo_copilot",
    "event_pipeline",
    "orchestrator",
})

ROGUE_OUTPUT_PATTERNS = (
    re.compile(r"override\s+(p1|p2|p3|filter)", re.I),
    re.compile(r"disable\s+bsv32", re.I),
    re.compile(r"auto[- ]?deploy\s+strategy", re.I),
)


def assert_allowed_action(action: str) -> bool:
    if action in FORBIDDEN_ACTIONS:
        logger.warning("forbidden_action_blocked", action=action)
        return False
    return True


def assert_allowed_agent(agent: str) -> bool:
    if agent not in ALLOWED_AGENT_NAMES:
        logger.warning("unknown_agent_action", agent=agent)
        return False
    return True


def is_allowed_outbound_url(url: str) -> bool:
    """Restrict agent HTTP calls to configured infrastructure hosts."""
    if not url:
        return False
    try:
        host = (urlparse(url).hostname or "").lower()
    except Exception:
        return False
    if host in ("127.0.0.1", "localhost"):
        return True
    settings = get_settings()
    for raw in (
        settings.mt5_api_url,
        settings.desk_api_url,
        settings.forward_bot_api_url,
        settings.watchdog_api_url,
        settings.mission_control_public_url,
    ):
        if not raw:
            continue
        h = (urlparse(raw).hostname or "").lower()
        if h and host == h:
            return True
    return False


def scan_text_for_rogue_content(text: str) -> list[str]:
    flags = []
    for pat in ROGUE_OUTPUT_PATTERNS:
        if pat.search(text):
            flags.append(pat.pattern)
    return flags


def validate_agent_result(agent: str, result: dict[str, Any] | None) -> dict[str, Any]:
    """Sanity-check agent cycle output; returns validation metadata."""
    issues: list[str] = []
    if not assert_allowed_agent(agent):
        issues.append("unknown_agent")
    if not result:
        return {"ok": True, "issues": issues}

    blob = str(result)
    issues.extend(scan_text_for_rogue_content(blob))

    for key in ("risk_score", "infra_health_score", "live_pnl"):
        if key in result:
            val = result[key]
            if isinstance(val, (int, float)) and (math.isnan(val) or math.isinf(val)):
                issues.append(f"invalid_{key}")

    return {"ok": len(issues) == 0, "issues": issues}


def validate_briefing_against_snapshot(
    briefing: dict[str, Any],
    snapshot: dict[str, Any],
) -> dict[str, Any]:
    """Detect briefing metrics that diverge sharply from live snapshot (hallucination heuristic)."""
    flags: list[str] = []
    pnl = briefing.get("pnl") or {}
    brief_live = float(pnl.get("live_pnl") or 0)
    snap_live = float(snapshot.get("live_pnl") or snapshot.get("floating_pnl") or 0)
    if abs(brief_live - snap_live) > 500 and snap_live != 0:
        flags.append("live_pnl_divergence")

    brief_risk = float((briefing.get("risk") or {}).get("risk_score") or 0)
    snap_risk = float(snapshot.get("risk_score") or 0)
    if abs(brief_risk - snap_risk) > 0.35:
        flags.append("risk_score_divergence")

    text = briefing.get("rendered_markdown") or ""
    flags.extend(scan_text_for_rogue_content(str(text)))

    return {"verified": len(flags) == 0, "flags": flags}
