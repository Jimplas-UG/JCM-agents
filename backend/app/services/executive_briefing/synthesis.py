"""CEO strategic synthesis, action board, and commander assessment."""

from __future__ import annotations

from app.services.executive_briefing.context import BriefingContext
from app.services.executive_briefing.types import (
    ActionRow,
    AgentReport,
    DecisionRow,
    ExecutiveBriefingDocument,
    MissionStatus,
)


def overall_mission_status(reports: list[AgentReport], ctx: BriefingContext) -> MissionStatus:
    if any(r["mission_status"] == "RED" for r in reports):
        return "RED"
    if any(r["mission_status"] == "YELLOW" for r in reports):
        return "YELLOW"
    if ctx.alerts_critical:
        return "RED"
    return "GREEN"


def build_executive_summary(
    ctx: BriefingContext, reports: list[AgentReport], mission_status: MissionStatus
) -> list[str]:
    equity = float(ctx.state.account_equity or 0) if ctx.state else 0
    open_n = len(ctx.open_trades)
    drafts = len(ctx.marketing_drafts)
    infra_ok = ctx.infra_live.get("healthy", False) if ctx.infra_live else False

    paras = [
        (
            f"Billy, this is your Mission Control briefing for {ctx.today.strftime('%A, %d %B %Y')}. "
            f"Overall mission status is {mission_status}. "
            "Jimplas Capital Management is operating a systematic gold forward demo on BSv3.2 "
            "with full supervisory intelligence — trading infrastructure, risk, marketing, and governance — "
            "reporting into this single document."
        ),
        (
            f"What happened yesterday: {len(ctx.trades_yesterday)} trade-related events were logged; "
            f"{len(ctx.audits_yesterday)} decisions received audit explanations. "
            f"{'Infrastructure experienced no active failures at last check.' if infra_ok else 'Infrastructure requires your attention before market open.'}"
        ),
        (
            f"What is happening now: {open_n} open positions on the book; "
            f"demo account equity approximately ${equity:,.2f}; "
            f"{len(ctx.alerts_open)} alerts in queue (verify legacy vs. live); "
            f"{drafts} marketing drafts await your approval."
        ),
        (
            "Financial impact: Realized P&L reporting remains limited until trade-close events fully populate. "
            "Strategic impact: You can still direct capital, marketing, and partnerships — "
            "but public performance claims should wait for a closed-trade sample."
        ),
        (
            "Marketing and brand: The marketing agent regenerates fresh LinkedIn, X, and Instagram drafts daily. "
            "Approving three posts per week maintains visibility for advisory and Fintrix narratives."
        ),
        (
            "AI systems: Nine supervisory agents are designed to observe BSv3.2 without altering strategy logic. "
            "Today's briefing aggregates their views so you never need to read raw logs."
        ),
        (
            "Partnerships and growth: Lead with infrastructure credibility (Mission Control, observability, Uganda depth) "
            "rather than unverified live returns. Highest near-term ROI is execution reliability plus content approval."
        ),
    ]

    if mission_status == "RED":
        paras.append(
            "Immediate priority: Resolve any RED agent status before taking new strategic commitments today. "
            "Delay external announcements until infrastructure and risk are GREEN."
        )
    elif mission_status == "YELLOW":
        paras.append(
            "Proceed with normal CEO agenda but reserve 30 minutes for YELLOW items in the Decision Board below."
        )
    else:
        paras.append(
            "Conditions support focused execution on marketing approval, research queue clearance, and forward-demo monitoring."
        )

    return paras


def build_strategic_synthesis(
    ctx: BriefingContext, reports: list[AgentReport]
) -> dict[str, str]:
    infra = next((r for r in reports if "Infrastructure" in r["agent_name"]), None)
    mkt = next((r for r in reports if "Marketing" in r["agent_name"]), None)
    perf = next((r for r in reports if "Performance" in r["agent_name"]), None)

    return {
        "most_important": (
            "The most important thing in the company today is reliable execution of the BSv3.2 forward demo "
            "combined with visible brand momentum. Without fills and closes, analytics mislead; "
            "without marketing approval, growth stalls."
        ),
        "focus_today": (
            "Focus today on: (1) clearing false or legacy infra alerts, "
            "(2) approving 1–3 marketing drafts, "
            "(3) confirming trade-close pipeline for accurate P&L."
        ),
        "ignore_today": (
            "Ignore today: historical rejection logs before the AutoTrading fix, "
            "backtest-vs-live gap debates until 30 closed trades, "
            "non-critical research items older than 14 days without severity escalation."
        ),
        "highest_roi_opportunities": (
            "Highest ROI: Daily LinkedIn post approval (low effort, inbound leads); "
            "ensuring MT5 stack stays green (preserves signal capture); "
            "packaging infrastructure story for one partner conversation this week."
        ),
        "immediate_threats": (
            "Immediate threats: Agent scheduler not running (stale briefing); "
            "kill-switch breach if drawdown limits hit; "
            "publishing performance marketing before data integrity."
        ),
        "accelerate": (
            "Accelerate: trade_closed webhook backfill, daily executive briefing habit, "
            "podcast-to-social repurpose."
        ),
        "pause": (
            "Pause: capital scale-up on forward demo, new strategy variants, "
            "paid ads until organic content rhythm is consistent 30 days."
        ),
        "resource_allocation": (
            "Allocate CEO time 40% brand/partnerships, 30% execution oversight, 20% team delegation, 10% research review. "
            "Allocate technical resources to data pipeline and scheduler reliability first."
        ),
        "delegate": (
            "Delegate to COO/ops: VPS health checks, alert triage, scheduler monitoring. "
            "Delegate to marketing VA: draft formatting and scheduling after CEO approval. "
            "Delegate to quant lead: research queue first pass."
        ),
    }


def build_action_board(ctx: BriefingContext, reports: list[AgentReport]) -> list[ActionRow]:
    rows: list[ActionRow] = []
    prio = 1

    if ctx.infra_live and not ctx.infra_live.get("healthy"):
        rows.append(
            ActionRow(
                priority=prio,
                action="Restore full execution stack (MT5, forward bot, desk API)",
                owner="COO / Ops",
                deadline="Today 12:00",
                impact="Revenue — trading resumes",
            )
        )
        prio += 1

    if len(ctx.marketing_drafts) >= 3:
        rows.append(
            ActionRow(
                priority=prio,
                action="Approve top 3 marketing drafts for publication",
                owner="Billy Jimplas",
                deadline="Today EOD",
                impact="Growth — brand visibility",
            )
        )
        prio += 1

    if len(ctx.research_pending) > 0:
        rows.append(
            ActionRow(
                priority=prio,
                action=f"Review {min(5, len(ctx.research_pending))} research queue items",
                owner="Billy or Head of Quant",
                deadline="Within 48h",
                impact="Strategic — edge protection",
            )
        )
        prio += 1

    rows.append(
        ActionRow(
            priority=prio,
            action="Verify trade_closed events on last 3 open positions",
            owner="Ops",
            deadline="This week",
            impact="Financial — accurate CEO P&L",
        )
    )

    return rows[:6]


def build_decision_board(ctx: BriefingContext, reports: list[AgentReport]) -> list[DecisionRow]:
    decisions: list[DecisionRow] = []

    if ctx.risk and ctx.risk.kill_switch_recommended:
        decisions.append(
            DecisionRow(
                decision="Halt new live orders on forward demo (kill-switch)",
                why_it_matters="Drawdown limits breached — further trading increases loss and reputational risk.",
                recommendation="Approve halt until manual risk review completed.",
                expected_outcome="Capital preserved; time to diagnose without additional exposure.",
            )
        )

    if len(ctx.marketing_drafts) >= 5:
        decisions.append(
            DecisionRow(
                decision="Batch-approve or batch-reject marketing backlog",
                why_it_matters="Queue depth signals brand execution lag; competitors post daily.",
                recommendation="Approve 3 strongest drafts; reject outdated; delegate scheduling.",
                expected_outcome="Steady outbound rhythm without CEO bottleneck tomorrow.",
            )
        )

    if len(ctx.research_pending) > 2:
        decisions.append(
            DecisionRow(
                decision="Assign research queue owner (you vs. quant lead)",
                why_it_matters="Pending drift findings may contain edge warnings.",
                recommendation="Delegate triage; you approve only critical severity.",
                expected_outcome="Faster cycle time without auto-deploy risk.",
            )
        )

    perf = ctx.perf_today
    if perf and (perf.total_trades or 0) < 5:
        decisions.append(
            DecisionRow(
                decision="Defer external 'live performance' messaging",
                why_it_matters="Insufficient closed-trade sample for institutional credibility.",
                recommendation="Wait for 30+ closed trades with verified P&L.",
                expected_outcome="Protected brand trust when you eventually publish results.",
            )
        )

    return decisions


def build_commander_assessment(
    ctx: BriefingContext, reports: list[AgentReport], actions: list[ActionRow]
) -> dict[str, object]:
    immediate = []
    if actions:
        for a in actions[:3]:
            immediate.append(a["action"])
    while len(immediate) < 3:
        immediate.append(
            [
                "Open Mission Control and confirm all infrastructure services green.",
                "Approve one LinkedIn draft to maintain brand presence.",
                "Ask ops for trade-close confirmation on open book.",
            ][len(immediate)]
        )

    reasoning = (
        "As your Chief of Staff view: today is about execution credibility and visible leadership. "
        "The trading system generates opportunity only if MT5 and the forward bot stay green. "
        "The market sees Jimplas through your content and podcast — fifteen minutes on approvals "
        "outperforms hours revising strategy. Protect the mandate by not marketing returns until "
        "the data supports them. These three actions align operations, growth, and governance."
    )

    return {"immediate_actions": immediate, "reasoning": reasoning}
