"""Prometheus metrics for BSv3.2 supervisory platform."""

from prometheus_client import Counter, Gauge, Histogram, generate_latest

TRADE_EVENTS_TOTAL = Counter(
    "jcm_trade_events_total",
    "Total BSv3.2 trade events ingested",
    ["event_type", "symbol"],
)

FILTER_BLOCKS_TOTAL = Counter(
    "jcm_filter_blocks_total",
    "Total BSv3.2 filter block events",
    ["filter"],
)

ACTIVE_ALERTS = Gauge(
    "jcm_active_alerts",
    "Number of unacknowledged alerts",
    ["severity"],
)

RISK_SCORE = Gauge(
    "jcm_risk_score",
    "Current portfolio risk score (0-1)",
)

BSV32_STATUS = Gauge(
    "jcm_bsv32_running",
    "BSv3.2 engine running status (1=running)",
)

INFRA_HEALTH = Gauge(
    "jcm_infra_health_score",
    "Infrastructure health score (0-1)",
)

API_LATENCY = Histogram(
    "jcm_api_request_duration_seconds",
    "API request duration",
    ["endpoint", "method"],
)

EXECUTION_SLIPPAGE = Histogram(
    "jcm_execution_slippage_pips",
    "Trade execution slippage in pips",
    ["symbol"],
)

AGENT_CYCLE_DURATION = Histogram(
    "jcm_agent_cycle_duration_seconds",
    "Agent cycle execution duration",
    ["agent"],
)

MARKETING_CONTENT_QUEUE = Gauge(
    "jcm_marketing_draft_count",
    "Marketing content drafts awaiting human approval",
)


def update_operational_gauges(result: dict) -> None:
    """Update gauges from agent cycle results when present."""
    if "risk_score" in result:
        RISK_SCORE.set(float(result["risk_score"]))
    if "infra_health_score" in result:
        INFRA_HEALTH.set(float(result["infra_health_score"]))
    if "system_running" in result:
        BSV32_STATUS.set(1.0 if result.get("system_running") else 0.0)
    alerts = result.get("active_alerts")
    if isinstance(alerts, int):
        ACTIVE_ALERTS.labels(severity="all").set(alerts)


def metrics_response() -> bytes:
    return generate_latest()
