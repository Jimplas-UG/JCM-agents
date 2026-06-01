"""Executive briefing document structure."""

from datetime import date

from app.services.executive_briefing.markdown import render_executive_briefing
from app.services.executive_briefing.reporters import build_all_agent_reports
from app.services.executive_briefing.context import BriefingContext
def test_nine_agent_reports() -> None:
    ctx = BriefingContext(today=date(2026, 6, 1))
    reports = build_all_agent_reports(ctx)
    assert len(reports) == 9
    assert reports[0]["agent_name"]
    assert reports[0]["mission_status"] in ("GREEN", "YELLOW", "RED")


def test_render_includes_ceo_sections() -> None:
    doc = {
        "title": "JCM MISSION CONTROL\nDAILY EXECUTIVE BRIEFING",
        "briefing_date": "2026-06-01",
        "prepared_for": "Billy Jimplas, CEO",
        "mission_status": "GREEN",
        "executive_summary": ["Summary paragraph."],
        "agent_reports": [],
        "ceo_strategic_synthesis": {"focus_today": "Focus here."},
        "ceo_action_board": [{"priority": 1, "action": "Act", "owner": "CEO", "deadline": "Today", "impact": "High"}],
        "ceo_decision_board": [],
        "commander_assessment": {"immediate_actions": ["A", "B", "C"], "reasoning": "Because."},
    }
    md = render_executive_briefing(doc)
    assert "Billy" in md or "Executive Summary" in md
    assert "CEO Strategic Synthesis" in md
    assert "CEO Action Board" in md
    assert "Commander Assessment" in md
