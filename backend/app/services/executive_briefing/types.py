"""Types for the JCM Daily Executive Briefing."""

from __future__ import annotations

from typing import Literal, TypedDict

MissionStatus = Literal["GREEN", "YELLOW", "RED"]


class AgentReport(TypedDict):
    agent_name: str
    mission_status: MissionStatus
    key_events: list[str]
    performance_analysis: dict[str, list[str]]
    opportunities: list[str]
    risks: list[str]
    ceo_decisions_required: list[str]
    recommended_actions: list[str]


class ActionRow(TypedDict):
    priority: int
    action: str
    owner: str
    deadline: str
    impact: str


class DecisionRow(TypedDict):
    decision: str
    why_it_matters: str
    recommendation: str
    expected_outcome: str


class ExecutiveBriefingDocument(TypedDict, total=False):
    format_version: int
    title: str
    briefing_date: str
    prepared_for: str
    mission_status: MissionStatus
    executive_summary: list[str]
    agent_reports: list[AgentReport]
    ceo_strategic_synthesis: dict[str, str]
    ceo_action_board: list[ActionRow]
    ceo_decision_board: list[DecisionRow]
    commander_assessment: dict[str, object]
    rendered_markdown: str
    generated_at: str
