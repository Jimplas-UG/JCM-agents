"""Telegram notification copy for the daily CEO executive briefing."""

from __future__ import annotations

from typing import Any


def format_executive_briefing_telegram(
    briefing: dict[str, Any],
    *,
    ceo_name: str = "Billy Jimplas",
    mission_control_url: str = "",
) -> str:
    """Corporate-style alert for the Global CEO with a concise operational recap."""
    bdate = briefing.get("briefing_date", "today")
    status = str(briefing.get("mission_status", "GREEN")).upper()
    pnl = briefing.get("pnl") or {}
    risk = briefing.get("risk") or {}
    infra = briefing.get("infrastructure") or {}
    bsv32 = briefing.get("bsv32_system") or {}
    perf = briefing.get("performance_vs_baseline") or {}

    equity = float(pnl.get("account_equity") or 0)
    daily = float(pnl.get("daily_pnl") or 0)
    live = float(pnl.get("live_pnl") or 0)
    positions = int(pnl.get("open_positions") or 0)
    risk_score = float(risk.get("risk_score") or 0)
    dd = float(risk.get("drawdown_pct") or 0)
    health = float(infra.get("health_score") or 0) * 100
    regime = bsv32.get("market_regime") or "unknown"
    engine = bsv32.get("status") or "unknown"

    alerts = briefing.get("alerts") or []
    pending = briefing.get("pending_human_decisions") or []
    marketing = briefing.get("pending_marketing_content") or []
    alert_n = len(alerts) if isinstance(alerts, list) else 0
    pending_n = len(pending) if isinstance(pending, list) else 0
    mkt_n = len(marketing) if isinstance(marketing, list) else 0

    summaries = briefing.get("executive_summary") or []
    if not summaries and isinstance(briefing.get("executive_briefing"), dict):
        summaries = (briefing["executive_briefing"].get("executive_summary") or [])[:2]
    headline = summaries[0] if summaries else "Full multi-agent synthesis is available in Mission Control."

    wr = perf.get("win_rate")
    wr_txt = f"{float(wr) * 100:.0f}%" if wr is not None else "n/a"

    alloc = briefing.get("allocator_progress") or {}
    alloc_score = int(alloc.get("progress_score") or 0)
    alloc_ready = "YES" if alloc.get("check_ready") else "NO"
    alloc_gates = f"{alloc.get('gates_passed', 0)}/{alloc.get('gates_total', 9)}"

    lines = [
        "*JIMPLAS CAPITAL MANAGEMENT*",
        "*Daily Executive Intelligence Brief*",
        "",
        f"Good morning, *{ceo_name}* — Global CEO",
        "",
        f"Your executive briefing for *{bdate}* has been prepared and is ready for your review.",
        "",
        f"*Mission posture:* `{status}`",
        f"• Account equity: `${equity:,.0f}` · Daily P&L: `${daily:+,.0f}` · Floating: `${live:+,.0f}`",
        f"• Open positions: `{positions}` · Risk score: `{risk_score:.1f}` · Drawdown: `{dd:.1f}%`",
        f"• Infrastructure health: `{health:.0f}%` · BSv3.2 engine: `{engine}` · Regime: `{regime}`",
        f"• Performance (today): win rate `{wr_txt}`",
        f"• Allocator progress: `{alloc_score}/100` · check-ready `{alloc_ready}` · gates `{alloc_gates}`",
        "",
        "*Executive recap:*",
        f"_{headline}_",
        "",
        f"*Attention queue:* `{alert_n}` active alerts · `{pending_n}` decisions pending · `{mkt_n}` marketing drafts",
        "",
        "Please open Mission Control for the full synthesis, CEO action board, and agent-level reports.",
    ]
    if mission_control_url:
        lines.append("")
        lines.append(f"[Open Mission Control]({mission_control_url})")
    lines.extend(
        [
            "",
            "— JCM CEO Copilot · BSv3.2 Supervisory Platform",
            "_Confidential — executive use only_",
        ]
    )
    return "\n".join(lines)
