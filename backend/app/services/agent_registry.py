"""Single source of truth for agent classes, intervals, and descriptions."""

from __future__ import annotations

from app.agents import (
    CeoCopilotAgent,
    ExecutionQualityAgent,
    ExplainabilityAgent,
    InfrastructureResilienceAgent,
    MarketingAgent,
    PerformanceIntelligenceAgent,
    PortfolioRiskOrchestrator,
    QuantMemoryAgent,
    ResearchEvolutionAgent,
)
from app.config import get_settings

AGENT_CLASSES: dict[str, type] = {
    "infra_resilience": InfrastructureResilienceAgent,
    "portfolio_risk": PortfolioRiskOrchestrator,
    "execution_quality": ExecutionQualityAgent,
    "performance_intel": PerformanceIntelligenceAgent,
    "research_evolution": ResearchEvolutionAgent,
    "quant_memory": QuantMemoryAgent,
    "explainability": ExplainabilityAgent,
    "marketing_agent": MarketingAgent,
    "ceo_copilot": CeoCopilotAgent,
}

AGENT_DESCRIPTIONS: dict[str, str] = {
    "quant_memory": "Records BSv3.2 trade events and system snapshots",
    "performance_intel": "Win rate, expectancy, edge decay analytics",
    "infra_resilience": "VPS/API health monitoring and remediation",
    "portfolio_risk": "Exposure, correlation, drawdown assessment",
    "execution_quality": "Slippage, spread, fill speed metrics",
    "explainability": "Structured audit trail for BSv3.2 decisions",
    "research_evolution": "Drift detection and human review queue",
    "ceo_copilot": "Executive briefing and dashboard overview",
    "marketing_agent": "Brand content drafts and trend signals",
}

# Agents whose scheduled cycle is ingest-driven; skip idle heartbeats.
INGEST_DRIVEN_AGENTS = frozenset({"quant_memory", "explainability"})


def agent_schedule() -> dict[str, tuple[type, int]]:
    settings = get_settings()
    marketing_interval = max(3600, settings.marketing_cycle_hours * 3600)
    return {
        "infra_resilience": (InfrastructureResilienceAgent, 30),
        "portfolio_risk": (PortfolioRiskOrchestrator, 60),
        "execution_quality": (ExecutionQualityAgent, 120),
        "performance_intel": (PerformanceIntelligenceAgent, 3600),
        "research_evolution": (ResearchEvolutionAgent, 7200),
        "ceo_copilot": (CeoCopilotAgent, 300),
        "quant_memory": (QuantMemoryAgent, 300),
        "explainability": (ExplainabilityAgent, 600),
        "marketing_agent": (MarketingAgent, marketing_interval),
    }


def format_interval(seconds: int) -> str:
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h"
