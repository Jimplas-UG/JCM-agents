"""Pydantic schemas for BSv3.2 event ingestion and API responses."""

from datetime import date, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field


class FilterStateMap(BaseModel):
    """BSv3.2 filter pass/block states — observational only."""

    nfp_blackout: str | None = None
    yield_filter: str | None = None
    dxy_filter: str | None = None
    ath_zone: str | None = None
    geopolitical: str | None = None
    chop_zone: str | None = None
    buy_path: str | None = None
    risk_gating: str | None = None
    watchdog: str | None = None
    multi_condition: str | None = None
    execution_filter: str | None = None


class VpsHealthSnapshot(BaseModel):
    cpu_pct: float | None = None
    ram_pct: float | None = None
    disk_pct: float | None = None
    mt5_connected: bool | None = None


class TradeEventIngest(BaseModel):
    """Inbound event from BSv3.2 execution layer webhook."""

    event_id: str
    event_type: str
    timestamp: datetime | None = None
    symbol: str
    direction: str | None = None
    lot_size: float | None = None
    entry_price: float | None = None
    exit_price: float | None = None
    stop_loss: float | None = None
    take_profit: float | None = None
    requested_price: float | None = None
    filled_price: float | None = None
    slippage_pips: float | None = None
    spread_at_entry: float | None = None
    spread_avg_24h: float | None = None
    execution_latency_ms: int | None = None
    pips: float | None = None
    r_multiple: float | None = None
    outcome: str = "open"
    pnl_usd: float | None = None
    filter_states: dict[str, str] = Field(default_factory=dict)
    filters_passed: list[str] = Field(default_factory=list)
    filters_blocked: list[str] = Field(default_factory=list)
    market_regime: str = "unknown"
    trading_session: str = "off_session"
    dxy_value: float | None = None
    dxy_state: str | None = None
    yield_10y: float | None = None
    yield_state: str | None = None
    volatility_state: str | None = None
    geopolitical_flag: bool = False
    ath_zone_active: bool = False
    chop_zone_active: bool = False
    nfp_blackout_active: bool = False
    bsv32_confidence: float | None = None
    bsv32_version: str = "3.2"
    vps_health: VpsHealthSnapshot | None = None
    raw_payload: dict[str, Any] | None = None


class FilterBlockIngest(BaseModel):
    event_id: str
    timestamp: datetime | None = None
    symbol: str
    direction: str | None = None
    blocked_by: list[str]
    filter_states: dict[str, str] = Field(default_factory=dict)
    market_regime: str = "unknown"
    trading_session: str = "off_session"
    dxy_state: str | None = None
    yield_state: str | None = None
    raw_payload: dict[str, Any] | None = None


class SystemStateIngest(BaseModel):
    bsv32_status: str
    nfp_blackout: bool = False
    yield_filter_state: str | None = None
    dxy_filter_state: str | None = None
    ath_zone_active: bool = False
    geopolitical_active: bool = False
    chop_zone_active: bool = False
    risk_gating_active: bool = False
    watchdog_ok: bool = True
    mt5_connected: bool = False
    desk_api_ok: bool = False
    forward_bot_ok: bool = False
    watchdog_api_ok: bool = False
    open_positions: int = 0
    account_equity: float | None = None
    account_balance: float | None = None
    floating_pnl: float | None = None
    daily_pnl: float | None = None
    drawdown_pct: float | None = None
    market_regime: str = "unknown"
    raw_snapshot: dict[str, Any] | None = None


class TradeEventResponse(BaseModel):
    id: UUID
    event_id: str
    event_type: str
    created_at: datetime
    symbol: str
    direction: str | None
    outcome: str
    pnl_usd: Decimal | None
    market_regime: str
    trading_session: str
    bsv32_confidence: Decimal | None

    model_config = {"from_attributes": True}


class DashboardOverview(BaseModel):
    bsv32_status: str
    system_running: bool
    nfp_blackout: bool
    live_pnl: float
    floating_pnl: float
    daily_pnl: float
    open_positions: int
    risk_score: float
    market_regime: str
    infra_health_score: float
    active_alerts: int
    pending_reviews: int
    mt5_connected: bool
    last_updated: datetime


class AlertResponse(BaseModel):
    id: UUID
    created_at: datetime
    agent_source: str
    severity: str
    title: str
    message: str
    acknowledged: bool

    model_config = {"from_attributes": True}


class PerformanceReportResponse(BaseModel):
    report_date: date
    total_trades: int
    win_rate: float | None
    expectancy: float | None
    avg_r_multiple: float | None
    total_pnl_usd: float | None
    edge_decay_score: float | None
    anomaly_flags: list

    model_config = {"from_attributes": True}


class ResearchFindingResponse(BaseModel):
    id: UUID
    created_at: datetime
    title: str
    finding_type: str
    severity: str
    recommendation: str
    status: str
    evidence: dict

    model_config = {"from_attributes": True}
