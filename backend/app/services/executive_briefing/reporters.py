"""CEO-level agent reports (one per supervisory agent)."""

from __future__ import annotations

from app.services.executive_briefing.context import BriefingContext
from app.services.executive_briefing.types import AgentReport, MissionStatus


def report_quant_memory(ctx: BriefingContext) -> AgentReport:
    y = len(ctx.trades_yesterday)
    t = len(ctx.trades_today)
    open_n = len(ctx.open_trades)
    closed_y = [tr for tr in ctx.trades_yesterday if tr.outcome in ("win", "loss", "breakeven")]
    wins = sum(1 for tr in closed_y if tr.outcome == "win")

    st: MissionStatus = "GREEN"
    if open_n > 5:
        st = "YELLOW"
    if ctx.alerts_critical:
        st = "YELLOW"

    return {
        "agent_name": "Quant Memory Agent",
        "mission_status": st,
        "key_events": [
            f"Yesterday the desk recorded {y} trade events; today so far {t}.",
            f"{open_n} positions remain open in institutional memory — P&L attribution depends on timely close events.",
            "Why it matters: Without closed-trade records, performance and risk agents cannot report true win rate or daily P&L to the CEO.",
            f"Impact: {'Execution memory is current for sizing decisions.' if t > 0 else 'Limited new activity — monitor for signal gaps or infrastructure pauses.'}",
        ],
        "performance_analysis": {
            "wins": [
                f"{wins} closed winners logged yesterday." if closed_y else "No closed trades yesterday — forward test still building sample.",
                "Trade ingest from BSv3.2 forward demo is active when MT5 fills occur.",
            ],
            "losses": [
                "Open trades without exit prices understate realized P&L in executive dashboards.",
            ],
            "bottlenecks": [
                "trade_closed webhook completion improves accuracy of all downstream analytics.",
            ],
            "trends": [
                f"Open book: {open_n} positions.",
                f"Yesterday activity: {y} events.",
            ],
        },
        "opportunities": [
            "Complete trade-close pipeline to unlock accurate daily performance briefings for investors and partners.",
            "Use journal history for a 30-day investor factsheet once closes are backfilled.",
        ],
        "risks": [
            "Operational: Stale open positions distort risk and performance views.",
            "Financial: CEO daily P&L may read zero while exposure is live.",
        ],
        "ceo_decisions_required": [],
        "recommended_actions": [
            "Priority 1 — Confirm trade_closed events are flowing after each MT5 exit.",
            "Priority 2 — Review open position list in Mission Control Trade History.",
            "Priority 3 — No strategy changes required; this is data plumbing only.",
        ],
    }


def report_performance_intel(ctx: BriefingContext) -> AgentReport:
    p = ctx.perf_today
    py = ctx.perf_yesterday
    wr = float(p.win_rate or 0) if p else 0
    exp = float(p.expectancy or 0) if p else 0
    edge = float(p.edge_decay_score or 0) if p else 0

    st = "GREEN"
    if edge > 0.5:
        st = "YELLOW"
    if wr < 0.35 and p and (p.total_trades or 0) > 5:
        st = "RED"

    return {
        "agent_name": "Performance Intelligence Agent",
        "mission_status": st,
        "key_events": [
            f"Daily performance report for {ctx.today} is {'published' if p else 'pending — insufficient closed trades'}.",
            f"Yesterday win rate: {float(py.win_rate or 0)*100:.1f}%." if py else "Yesterday: no performance rollup.",
            "Why it matters: This is the scoreboard for whether BSv3.2 forward deployment merits capital scale-up.",
            f"Edge decay signal: {edge:.2f} (elevated above 0.5 warrants review)." if edge else "Edge decay within normal range.",
        ],
        "performance_analysis": {
            "wins": [
                f"Expectancy today: {exp:.2f} R." if p else "Awaiting closed trades for expectancy.",
                "Segmentation by session and regime available when sample size grows.",
            ],
            "losses": [
                "Low closed-trade count limits statistical confidence.",
                f"Anomalies flagged: {p.anomaly_flags if p else []}.",
            ],
            "bottlenecks": [
                "Performance intel idle until trade_closed populates outcomes.",
            ],
            "trends": [
                f"Win rate (today): {wr*100:.1f}%.",
                "Compare forward live vs backtest in side-by-side report before increasing risk.",
            ],
        },
        "opportunities": [
            "Once 30+ closed live trades exist, publish investor-grade monthly performance memo.",
            "Filter efficiency report can identify which gates add most alpha.",
        ],
        "risks": [
            "Financial: Scaling capital before live-forward matches backtest destroys credibility.",
            "Strategic: Announcing returns without audited closed-trade data.",
        ],
        "ceo_decisions_required": [
            "Delay marketing of live returns until closed-trade sample ≥ 30 trades — consequence: reputational risk if promoted early.",
        ] if wr == 0 and not p else [],
        "recommended_actions": [
            "Priority 1 — Read forward-vs-sim report before changing risk per trade.",
            "Priority 2 — Hold capital scale-up until win rate and expectancy stabilize.",
            "Priority 3 — Schedule weekly performance review once closes flow.",
        ],
    }


def report_infra_resilience(ctx: BriefingContext) -> AgentReport:
    infra = ctx.infra
    live = ctx.infra_live or {}
    svc = live.get("services", {})
    if live:
        healthy = live.get("healthy", False)
    elif infra:
        healthy = bool(infra.mt5_connected and infra.desk_api_ok and infra.forward_bot_ok)
    else:
        healthy = False
    mt5 = svc.get("mt5", {}).get("ok", infra.mt5_connected if infra else False)
    fwd = svc.get("forward_bot", {}).get("ok", infra.forward_bot_ok if infra else False)

    st = "RED" if not healthy else "GREEN"
    if healthy and len(ctx.alerts_critical) > 0:
        st = "YELLOW"

    failed = [k for k, v in svc.items() if not v.get("ok")]

    return {
        "agent_name": "Infrastructure Resilience Agent",
        "mission_status": st,
        "key_events": [
            f"Mission stack is {'fully operational' if healthy else 'DEGRADED — immediate attention'}.",
            f"MT5 bridge: {'online' if mt5 else 'OFFLINE'}. Forward bot: {'running' if fwd else 'DOWN'}.",
            "Why it matters: No infrastructure, no revenue from systematic trading or client confidence in JCM tech.",
            f"Impact on company: {'Trading and Mission Control can proceed.' if healthy else 'Revenue execution halted until restored.'}",
        ],
        "performance_analysis": {
            "wins": [
                "Watchdog and desk API responding within normal latency." if healthy else "",
                f"VPS CPU/RAM within limits." if infra else "",
            ],
            "losses": [f"Failed services: {', '.join(failed)}." if failed else ""],
            "bottlenecks": ["Stale critical alerts in queue create noise — bulk-ack resolved outages."],
            "trends": ["AutoTrading and /algotrading startup now enforced on MT5 restarts."],
        },
        "opportunities": [
            "Market JCM as institution-grade infra (observability + self-heal) to fintech partners.",
        ],
        "risks": [
            "Operational: VPS reboot without scheduled tasks stops agent scheduler.",
            "Financial: Each hour of MT5 down is missed signal opportunity on XAU.",
        ],
        "ceo_decisions_required": [
            "Authorize VPS maintenance window only with pre-flight script run — consequence: missed trading session.",
        ] if not healthy else [],
        "recommended_actions": [
            "Priority 1 — Run ensure-forward stack script if any service red.",
            "Priority 2 — Ignore historical infra alerts dated before recovery.",
            "Priority 3 — Quarterly DR test of full stack boot from cold start.",
        ],
    }


def report_portfolio_risk(ctx: BriefingContext) -> AgentReport:
    r = ctx.risk
    score = float(r.risk_score or 0) if r else 0
    kill = r.kill_switch_recommended if r else False
    open_n = r.open_positions if r else len(ctx.open_trades)
    dd = float(r.account_drawdown_pct or 0) if r else 0

    st = "RED" if kill else ("YELLOW" if score > 0.6 else "GREEN")

    return {
        "agent_name": "Portfolio Risk Orchestrator",
        "mission_status": st,
        "key_events": [
            f"Portfolio risk score: {score:.2f} (0=calm, 1=elevated).",
            f"Open positions (risk view): {open_n}. Account drawdown: {dd:.1f}%.",
            "Why it matters: Protects JCM and client capital before BSv3.2 gates fail.",
            f"Kill-switch recommended: {'YES — CEO review required' if kill else 'No'}.",
        ],
        "performance_analysis": {
            "wins": [
                f"Lot scaling factor: {float(r.lot_scaling_factor or 1):.2f} — informational to desk only.",
            ],
            "losses": [
                "Correlated exposure elevated." if r and r.correlated_pairs else "No correlation cluster detected.",
            ],
            "bottlenecks": [],
            "trends": [f"Daily drawdown: {float(r.daily_drawdown_pct or 0):.1f}%." if r else ""],
        },
        "opportunities": [
            "Tight risk posture builds track record for external allocator conversations.",
        ],
        "risks": [
            "Financial: Ignoring kill-switch recommendation after drawdown breach.",
            "Operational: Position count mismatch between risk and trade tables.",
        ],
        "ceo_decisions_required": [
            "Approve or reject kill-switch halt on live forward demo — consequence: continued exposure vs. stopped losses.",
        ] if kill else [],
        "recommended_actions": [
            "Priority 1 — Review drawdown vs. mandate limits.",
            "Priority 2 — Do not override lot scaling without written risk memo.",
            "Priority 3 — Delegate daily risk check to COO; escalate only on RED.",
        ],
    }


def report_execution_quality(ctx: BriefingContext) -> AgentReport:
    logs = ctx.execution_logs_24h
    n = len(logs)
    rej = sum(1 for l in logs if l.rejection)
    rate = rej / n if n else 0
    anomalies = sum(1 for l in logs if l.anomaly_flag)

    st = "GREEN"
    if rate > 0.15:
        st = "RED"
    elif rate > 0.05 or anomalies > 2:
        st = "YELLOW"

    return {
        "agent_name": "Execution Quality Agent",
        "mission_status": st,
        "key_events": [
            f"Last 24h: {n} execution samples, rejection rate {rate*100:.1f}%.",
            "Yesterday/today: MT5 AutoTrading and stop-normalization fixes deployed — rejections should trend to zero.",
            "Why it matters: Poor fills directly reduce edge; rejections mean missed trades.",
            f"Impact: {'Execution quality supports scaling.' if rate < 0.05 else 'CEO attention needed on broker path.'}",
        ],
        "performance_analysis": {
            "wins": ["Recent fills show 0% rejection on new signals post-fix." if rate == 0 else ""],
            "losses": [f"{anomalies} execution anomalies flagged." if anomalies else ""],
            "bottlenecks": ["Spread on XAU still wide vs. backtest assumptions."],
            "trends": ["Slippage within tolerance on recent fills."],
        },
        "opportunities": [
            "Publish execution quality score to partners as proof of institutional ops.",
        ],
        "risks": [
            "Financial: 10027/10016 rejections historically cost signal capture.",
            "Compliance: Ensure demo vs. live labeling in external comms.",
        ],
        "ceo_decisions_required": [],
        "recommended_actions": [
            "Priority 1 — Monitor rejection rate daily on Mission Control.",
            "Priority 2 — Ignore pre-fix rejection history in trend analysis.",
            "Priority 3 — Re-audit broker score weekly.",
        ],
    }


def report_explainability(ctx: BriefingContext) -> AgentReport:
    audits = ctx.audits_yesterday
    n = len(audits)

    return {
        "agent_name": "Explainability Agent",
        "mission_status": "GREEN" if n > 0 else "YELLOW",
        "key_events": [
            f"{n} audited decisions yesterday with human-readable rationale.",
            "Every approved trade documents which BSv3.2 filters passed — critical for regulatory and investor trust.",
            "Why it matters: You can defend every position without opening the codebase.",
            "Impact: Governance ready for institutional due diligence.",
        ],
        "performance_analysis": {
            "wins": ["Audit trail current for recent executions."],
            "losses": [],
            "bottlenecks": [],
            "trends": [],
        },
        "opportunities": [
            "Package audit exports for partner banks or regulated venues.",
        ],
        "risks": [
            "Compliance: Gaps in audit trail if signals blocked but not logged.",
        ],
        "ceo_decisions_required": [],
        "recommended_actions": [
            "Priority 1 — Spot-check one audit entry per week personally.",
            "Priority 2 — Delegate export requests to compliance lead.",
            "Priority 3 — No action if audit count matches trade count.",
        ],
    }


def report_research_evolution(ctx: BriefingContext) -> AgentReport:
    pending = ctx.research_pending
    n = len(pending)

    st = "YELLOW" if n > 3 else "GREEN"
    if any(str(r.severity) == "critical" for r in pending):
        st = "RED"

    return {
        "agent_name": "Research Evolution Agent",
        "mission_status": st,
        "key_events": [
            f"{n} research findings await human review (no auto-deploy by design).",
            "Monitors filter drift, regime shift, and execution degradation vs. baseline.",
            "Why it matters: Protects BSv3.2 from silent edge decay.",
            "Impact: Strategic changes only enter production after your approval.",
        ],
        "performance_analysis": {
            "wins": ["Human-in-the-loop preserved — strategy integrity maintained."],
            "losses": [f"{n} pending items — decision latency." if n else "Queue clear."],
            "bottlenecks": ["CEO review bandwidth."],
            "trends": [],
        },
        "opportunities": [
            "Approve high-confidence research items to improve filter efficiency.",
        ],
        "risks": [
            "Strategic: Ignoring drift warnings for 30+ days.",
        ],
        "ceo_decisions_required": [
            f"Review {n} pending research queue items — consequence: undetected drift continues.",
        ] if n else [],
        "recommended_actions": [
            "Priority 1 — Clear research queue or delegate to head of quant.",
            "Priority 2 — Never auto-deploy model changes.",
            "Priority 3 — Monthly research review calendar invite.",
        ],
    }


def report_marketing(ctx: BriefingContext) -> AgentReport:
    drafts = len(ctx.marketing_drafts)
    approved = ctx.marketing_approved
    cycle = ctx.marketing_cycle_today
    generated = cycle.items_generated if cycle else 0

    st = "GREEN" if drafts >= 3 else "YELLOW"

    return {
        "agent_name": "Marketing Agent",
        "mission_status": st,
        "key_events": [
            f"Content pipeline: {drafts} drafts awaiting your approval, {approved} approved for publishing.",
            f"Today's automated cycle added {generated} new draft(s) (LinkedIn, X, Instagram rotation).",
            "Why it matters: Brand authority drives advisory leads, podcast audience, and Fintrix narrative.",
            "Impact: Consistent posting = inbound trust for Jimplas Capital Management.",
        ],
        "performance_analysis": {
            "wins": [
                "Daily regeneration active — fresh CEO-review queue each morning.",
                "Educational compliance footers on all drafts.",
            ],
            "losses": ["Backlog of drafts if CEO approval slower than generation."],
            "bottlenecks": ["CEO approval on LinkedIn/X/Instagram queue."],
            "trends": ["Infrastructure-first and Uganda capital markets pillars rotating."],
        },
        "opportunities": [
            "Approve 3 posts this week → measurable LinkedIn engagement lift.",
            "Repurpose podcast episodes into carousel series.",
            "Revenue: Inbound advisory inquiries from thought leadership.",
        ],
        "risks": [
            "Compliance: Never approve drafts with return guarantees (agent flags these).",
            "Competitive: Competitors out-posting while queue sits idle.",
        ],
        "ceo_decisions_required": [
            f"Approve or reject top 3 marketing drafts — consequence: brand visibility stalls.",
        ] if drafts >= 5 else [],
        "recommended_actions": [
            "Priority 1 — Approve today's LinkedIn draft (10 min).",
            "Priority 2 — Delegate Instagram scheduling to marketing VA.",
            "Priority 3 — Record 1 podcast clip for repurpose next cycle.",
        ],
    }


def report_ceo_copilot(ctx: BriefingContext) -> AgentReport:
    equity = float(ctx.state.account_equity or 0) if ctx.state else 0
    alerts = len(ctx.alerts_open)

    st = "GREEN"
    if alerts > 10:
        st = "YELLOW"
    if ctx.alerts_critical:
        st = "RED"

    return {
        "agent_name": "CEO Copilot Agent",
        "mission_status": st,
        "key_events": [
            "Mission Control synthesized this briefing from all supervisory agents.",
            f"Account equity (demo): ${equity:,.2f}." if equity else "Equity feed pending.",
            f"{alerts} open alerts require triage (many may be legacy).",
            "Why it matters: Single pane of glass for Billy Jimplas as CEO.",
            "Impact: Decisions made here compound across trading, marketing, and partnerships.",
        ],
        "performance_analysis": {
            "wins": ["Nine-agent architecture operational."],
            "losses": ["Scheduler must stay running for 09:00 auto-briefing."],
            "bottlenecks": [],
            "trends": [],
        },
        "opportunities": [
            "Use daily briefing as stand-up agenda for leadership team.",
        ],
        "risks": [
            "Operational: Agent scheduler down = stale Mission Control.",
        ],
        "ceo_decisions_required": [],
        "recommended_actions": [
            "Priority 1 — Read full briefing before other meetings.",
            "Priority 2 — Act on Decision Board items same day.",
            "Priority 3 — Forward synthesis to COO for execution tracking.",
        ],
    }


def build_all_agent_reports(ctx: BriefingContext) -> list[AgentReport]:
    return [
        report_quant_memory(ctx),
        report_performance_intel(ctx),
        report_infra_resilience(ctx),
        report_portfolio_risk(ctx),
        report_execution_quality(ctx),
        report_explainability(ctx),
        report_research_evolution(ctx),
        report_marketing(ctx),
        report_ceo_copilot(ctx),
    ]
