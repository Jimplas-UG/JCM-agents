"""Render executive briefing as CEO-readable markdown."""

from __future__ import annotations

from app.services.executive_briefing.types import AgentReport, ExecutiveBriefingDocument


def render_executive_briefing(doc: ExecutiveBriefingDocument) -> str:
    lines: list[str] = []
    lines.append(doc.get("title", "JCM MISSION CONTROL\nDAILY EXECUTIVE BRIEFING"))
    lines.append("")
    lines.append(f"**Date:** {doc.get('briefing_date', '')}")
    lines.append("")
    lines.append("**Prepared For:**")
    lines.append(doc.get("prepared_for", "Billy Jimplas, CEO"))
    lines.append("")
    lines.append(f"**Mission Status:** {doc.get('mission_status', 'GREEN')}")
    lines.append("")
    lines.append("## Executive Summary")
    lines.append("")
    for p in doc.get("executive_summary", []):
        lines.append(p)
        lines.append("")

    alloc = doc.get("allocator_progress") or {}
    if alloc:
        lines.append("## Allocator Progress (LP Due Diligence)")
        lines.append("")
        ready = "YES" if alloc.get("check_ready") else "NO"
        lines.append(
            f"**Check-ready:** {ready} · **Progress:** {alloc.get('progress_score', 0)}/100 "
            f"· **Gates:** {alloc.get('gates_passed', 0)}/{alloc.get('gates_total', 9)}"
        )
        lines.append("")
        if alloc.get("headline"):
            lines.append(alloc["headline"])
            lines.append("")
        for g in alloc.get("gates") or []:
            mark = "PASS" if g.get("pass") else "FAIL"
            lines.append(
                f"- [{mark}] {g.get('label', g.get('code', ''))}: {g.get('current', '')} "
                f"(target {g.get('target', '')})"
            )
        lines.append("")
        blockers = alloc.get("blockers") or alloc.get("next_milestones") or []
        if blockers:
            lines.append("**Next milestones:**")
            for b in blockers:
                lines.append(f"- {b}")
            lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("## Agent Reports")
    lines.append("")

    for report in doc.get("agent_reports", []):
        lines.extend(_render_agent_report(report))
        lines.append("---")
        lines.append("")

    syn = doc.get("ceo_strategic_synthesis", {})
    lines.append("## CEO Strategic Synthesis")
    lines.append("")
    q = [
        ("1. Most important", "most_important"),
        ("2. Focus today", "focus_today"),
        ("3. Ignore today", "ignore_today"),
        ("4. Highest ROI opportunities", "highest_roi_opportunities"),
        ("5. Immediate threats", "immediate_threats"),
        ("6. Accelerate", "accelerate"),
        ("7. Pause", "pause"),
        ("8. Resource allocation", "resource_allocation"),
        ("9. Delegate", "delegate"),
    ]
    for label, key in q:
        if syn.get(key):
            lines.append(f"**{label}:** {syn[key]}")
            lines.append("")

    lines.append("## CEO Action Board")
    lines.append("")
    lines.append("| Priority | Action | Owner | Deadline | Impact |")
    lines.append("| -------- | ------ | ----- | -------- | ------ |")
    for row in doc.get("ceo_action_board", []):
        lines.append(
            f"| {row['priority']} | {row['action']} | {row['owner']} | {row['deadline']} | {row['impact']} |"
        )
    lines.append("")

    lines.append("## Decisions Billy Must Make Today")
    lines.append("")
    for i, d in enumerate(doc.get("ceo_decision_board", []), 1):
        lines.append(f"### {i}. {d['decision']}")
        lines.append(f"- **Why it matters:** {d['why_it_matters']}")
        lines.append(f"- **Recommendation:** {d['recommendation']}")
        lines.append(f"- **Expected outcome:** {d['expected_outcome']}")
        lines.append("")

    if not doc.get("ceo_decision_board"):
        lines.append("*No mandatory decisions flagged — proceed with Action Board.*")
        lines.append("")

    cmd = doc.get("commander_assessment", {})
    lines.append("## Mission Control Commander Assessment")
    lines.append("")
    lines.append('**If I were CEO today, these are the 3 actions I would take immediately:**')
    lines.append("")
    for i, act in enumerate(cmd.get("immediate_actions", []), 1):
        lines.append(f"{i}. {act}")
    lines.append("")
    lines.append(cmd.get("reasoning", ""))

    return "\n".join(lines)


def _render_agent_report(r: AgentReport) -> list[str]:
    out: list[str] = []
    out.append(f"### {r['agent_name']}")
    out.append("")
    out.append(f"**Mission Status:** {r['mission_status']}")
    out.append("")
    out.append("**Key Events**")
    for e in r.get("key_events", []):
        if e:
            out.append(f"- {e}")
    out.append("")
    pa = r.get("performance_analysis", {})
    out.append("**Performance Analysis**")
    for section in ("wins", "losses", "bottlenecks", "trends"):
        items = [x for x in pa.get(section, []) if x]
        if items:
            out.append(f"- *{section.title()}:* " + "; ".join(items))
    out.append("")
    out.append("**Opportunities**")
    for o in r.get("opportunities", []):
        out.append(f"- {o}")
    out.append("")
    out.append("**Risks**")
    for risk in r.get("risks", []):
        out.append(f"- {risk}")
    out.append("")
    if r.get("ceo_decisions_required"):
        out.append("**CEO Decisions Required**")
        for d in r["ceo_decisions_required"]:
            out.append(f"- {d}")
        out.append("")
    out.append("**Recommended Actions**")
    for a in r.get("recommended_actions", []):
        out.append(f"- {a}")
    out.append("")
    return out
