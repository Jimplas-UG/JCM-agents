"""SQLAlchemy ORM models mirroring PostgreSQL schema."""

import enum
import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import (
    Boolean,
    Date,
    DateTime,
    Enum,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.session import Base


class ReviewStatus(str, enum.Enum):
    pending = "pending"
    approved = "approved"
    rejected = "rejected"
    deferred = "deferred"


class AlertSeverity(str, enum.Enum):
    info = "info"
    warning = "warning"
    critical = "critical"
    emergency = "emergency"


class TradeDirection(str, enum.Enum):
    long = "long"
    short = "short"


class TradeOutcome(str, enum.Enum):
    win = "win"
    loss = "loss"
    breakeven = "breakeven"
    open = "open"
    cancelled = "cancelled"


class MarketRegime(str, enum.Enum):
    trending_bull = "trending_bull"
    trending_bear = "trending_bear"
    ranging = "ranging"
    volatile = "volatile"
    low_vol = "low_vol"
    unknown = "unknown"


class TradingSession(str, enum.Enum):
    london = "london"
    new_york = "new_york"
    overlap = "overlap"
    off_session = "off_session"
    asia = "asia"


class EventType(str, enum.Enum):
    trade_executed = "trade_executed"
    trade_blocked = "trade_blocked"
    trade_closed = "trade_closed"
    filter_state_change = "filter_state_change"
    risk_parameter_change = "risk_parameter_change"
    kill_switch = "kill_switch"
    confidence_shift = "confidence_shift"
    system_state = "system_state"


class TradeEvent(Base):
    __tablename__ = "trade_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    event_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    event_type: Mapped[EventType] = mapped_column(
        Enum(EventType, name="event_type", create_type=False), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    symbol: Mapped[str] = mapped_column(String(16), nullable=False)
    direction: Mapped[TradeDirection | None] = mapped_column(
        Enum(TradeDirection, name="trade_direction", create_type=False)
    )
    lot_size: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    entry_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    exit_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    stop_loss: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    take_profit: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    requested_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    filled_price: Mapped[Decimal | None] = mapped_column(Numeric(18, 6))
    slippage_pips: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    spread_at_entry: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    spread_avg_24h: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    execution_latency_ms: Mapped[int | None] = mapped_column(Integer)
    pips: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    r_multiple: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    outcome: Mapped[TradeOutcome] = mapped_column(
        Enum(TradeOutcome, name="trade_outcome", create_type=False),
        default=TradeOutcome.open,
    )
    pnl_usd: Mapped[Decimal | None] = mapped_column(Numeric(14, 4))
    filter_states: Mapped[dict] = mapped_column(JSONB, default=dict)
    filters_passed: Mapped[list | None] = mapped_column(ARRAY(Text))
    filters_blocked: Mapped[list | None] = mapped_column(ARRAY(Text))
    market_regime: Mapped[MarketRegime] = mapped_column(
        Enum(MarketRegime, name="market_regime", create_type=False),
        default=MarketRegime.unknown,
    )
    trading_session: Mapped[TradingSession] = mapped_column(
        Enum(TradingSession, name="trading_session", create_type=False),
        default=TradingSession.off_session,
    )
    dxy_value: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    dxy_state: Mapped[str | None] = mapped_column(String(32))
    yield_10y: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    yield_state: Mapped[str | None] = mapped_column(String(32))
    volatility_state: Mapped[str | None] = mapped_column(String(32))
    geopolitical_flag: Mapped[bool] = mapped_column(Boolean, default=False)
    ath_zone_active: Mapped[bool] = mapped_column(Boolean, default=False)
    chop_zone_active: Mapped[bool] = mapped_column(Boolean, default=False)
    nfp_blackout_active: Mapped[bool] = mapped_column(Boolean, default=False)
    bsv32_confidence: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    bsv32_version: Mapped[str] = mapped_column(String(16), default="3.2")
    vps_cpu_pct: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    vps_ram_pct: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    vps_disk_pct: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    mt5_connected: Mapped[bool | None] = mapped_column(Boolean)
    raw_payload: Mapped[dict | None] = mapped_column(JSONB)

    execution_logs: Mapped[list["ExecutionQualityLog"]] = relationship(
        back_populates="trade_event"
    )


class FilterBlockEvent(Base):
    __tablename__ = "filter_block_events"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    event_id: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    symbol: Mapped[str] = mapped_column(String(16), nullable=False)
    direction: Mapped[str | None] = mapped_column(String(8))
    blocked_by: Mapped[list] = mapped_column(ARRAY(Text), nullable=False)
    filter_states: Mapped[dict] = mapped_column(JSONB, default=dict)
    market_regime: Mapped[str] = mapped_column(String(32), default="unknown")
    trading_session: Mapped[str] = mapped_column(String(32), default="off_session")
    dxy_state: Mapped[str | None] = mapped_column(String(32))
    yield_state: Mapped[str | None] = mapped_column(String(32))
    hypothetical_outcome: Mapped[str | None] = mapped_column(String(16))
    hypothetical_pips: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    counterfactual_evaluated: Mapped[bool] = mapped_column(Boolean, default=False)
    raw_payload: Mapped[dict | None] = mapped_column(JSONB)


class SystemStateSnapshot(Base):
    __tablename__ = "system_state_snapshots"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    bsv32_status: Mapped[str] = mapped_column(String(32), nullable=False)
    nfp_blackout: Mapped[bool] = mapped_column(Boolean, default=False)
    yield_filter_state: Mapped[str | None] = mapped_column(String(32))
    dxy_filter_state: Mapped[str | None] = mapped_column(String(32))
    ath_zone_active: Mapped[bool] = mapped_column(Boolean, default=False)
    geopolitical_active: Mapped[bool] = mapped_column(Boolean, default=False)
    chop_zone_active: Mapped[bool] = mapped_column(Boolean, default=False)
    risk_gating_active: Mapped[bool] = mapped_column(Boolean, default=False)
    watchdog_ok: Mapped[bool] = mapped_column(Boolean, default=True)
    mt5_connected: Mapped[bool] = mapped_column(Boolean, default=False)
    desk_api_ok: Mapped[bool] = mapped_column(Boolean, default=False)
    forward_bot_ok: Mapped[bool] = mapped_column(Boolean, default=False)
    watchdog_api_ok: Mapped[bool] = mapped_column(Boolean, default=False)
    open_positions: Mapped[int] = mapped_column(Integer, default=0)
    account_equity: Mapped[Decimal | None] = mapped_column(Numeric(14, 4))
    account_balance: Mapped[Decimal | None] = mapped_column(Numeric(14, 4))
    floating_pnl: Mapped[Decimal | None] = mapped_column(Numeric(14, 4))
    daily_pnl: Mapped[Decimal | None] = mapped_column(Numeric(14, 4))
    drawdown_pct: Mapped[Decimal | None] = mapped_column(Numeric(8, 4))
    market_regime: Mapped[MarketRegime] = mapped_column(
        Enum(MarketRegime, name="market_regime", create_type=False),
        default=MarketRegime.unknown,
    )
    raw_snapshot: Mapped[dict | None] = mapped_column(JSONB)


class InfraHealthLog(Base):
    __tablename__ = "infra_health_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    vps_cpu_pct: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    vps_ram_pct: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    vps_disk_pct: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    mt5_connected: Mapped[bool | None] = mapped_column(Boolean)
    mt5_latency_ms: Mapped[int | None] = mapped_column(Integer)
    desk_api_ok: Mapped[bool | None] = mapped_column(Boolean)
    desk_api_latency_ms: Mapped[int | None] = mapped_column(Integer)
    forward_bot_ok: Mapped[bool | None] = mapped_column(Boolean)
    forward_bot_latency_ms: Mapped[int | None] = mapped_column(Integer)
    watchdog_ok: Mapped[bool | None] = mapped_column(Boolean)
    network_ping_ms: Mapped[int | None] = mapped_column(Integer)
    execution_delay_ms: Mapped[int | None] = mapped_column(Integer)
    service_states: Mapped[dict] = mapped_column(JSONB, default=dict)
    alert_triggered: Mapped[bool] = mapped_column(Boolean, default=False)
    remediation_action: Mapped[str | None] = mapped_column(String(128))


class ExecutionQualityLog(Base):
    __tablename__ = "execution_quality_logs"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    trade_event_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("trade_events.id")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    symbol: Mapped[str] = mapped_column(String(16), nullable=False)
    slippage_pips: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    spread_at_exec: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    spread_avg: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    fill_speed_ms: Mapped[int | None] = mapped_column(Integer)
    rejection: Mapped[bool] = mapped_column(Boolean, default=False)
    rejection_reason: Mapped[str | None] = mapped_column(String(256))
    mt5_timeout: Mapped[bool] = mapped_column(Boolean, default=False)
    mt5_freeze: Mapped[bool] = mapped_column(Boolean, default=False)
    anomaly_flag: Mapped[bool] = mapped_column(Boolean, default=False)

    trade_event: Mapped["TradeEvent | None"] = relationship(
        back_populates="execution_logs"
    )


class RiskExposureSnapshot(Base):
    __tablename__ = "risk_exposure_snapshots"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    open_positions: Mapped[int] = mapped_column(Integer, default=0)
    total_exposure_lots: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    correlated_pairs: Mapped[list] = mapped_column(JSONB, default=list)
    correlation_risk_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    account_drawdown_pct: Mapped[Decimal | None] = mapped_column(Numeric(8, 4))
    daily_drawdown_pct: Mapped[Decimal | None] = mapped_column(Numeric(8, 4))
    risk_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    lot_scaling_factor: Mapped[Decimal] = mapped_column(Numeric(5, 4), default=1.0)
    kill_switch_recommended: Mapped[bool] = mapped_column(Boolean, default=False)
    trade_frequency_1h: Mapped[int] = mapped_column(Integer, default=0)
    alerts: Mapped[list] = mapped_column(JSONB, default=list)


class AuditTrail(Base):
    __tablename__ = "audit_trail"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    event_type: Mapped[EventType] = mapped_column(
        Enum(EventType, name="event_type", create_type=False), nullable=False
    )
    reference_id: Mapped[str | None] = mapped_column(String(64))
    summary: Mapped[str] = mapped_column(Text, nullable=False)
    explanation_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    human_readable: Mapped[str | None] = mapped_column(Text)
    severity: Mapped[AlertSeverity] = mapped_column(
        Enum(AlertSeverity, name="alert_severity", create_type=False),
        default=AlertSeverity.info,
    )


class PerformanceDaily(Base):
    __tablename__ = "performance_daily"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    report_date: Mapped[date] = mapped_column(Date, unique=True, nullable=False)
    total_trades: Mapped[int] = mapped_column(Integer, default=0)
    wins: Mapped[int] = mapped_column(Integer, default=0)
    losses: Mapped[int] = mapped_column(Integer, default=0)
    breakeven: Mapped[int] = mapped_column(Integer, default=0)
    win_rate: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    expectancy: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    avg_r_multiple: Mapped[Decimal | None] = mapped_column(Numeric(10, 4))
    total_pips: Mapped[Decimal | None] = mapped_column(Numeric(12, 4))
    total_pnl_usd: Mapped[Decimal | None] = mapped_column(Numeric(14, 4))
    max_drawdown_pct: Mapped[Decimal | None] = mapped_column(Numeric(8, 4))
    by_regime: Mapped[dict] = mapped_column(JSONB, default=dict)
    by_session: Mapped[dict] = mapped_column(JSONB, default=dict)
    by_dxy_state: Mapped[dict] = mapped_column(JSONB, default=dict)
    by_yield_state: Mapped[dict] = mapped_column(JSONB, default=dict)
    by_day_of_week: Mapped[dict] = mapped_column(JSONB, default=dict)
    filter_efficiency: Mapped[dict] = mapped_column(JSONB, default=dict)
    edge_decay_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    anomaly_flags: Mapped[list] = mapped_column(JSONB, default=list)
    report_json: Mapped[dict | None] = mapped_column(JSONB)


class ResearchReviewQueue(Base):
    __tablename__ = "research_review_queue"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    title: Mapped[str] = mapped_column(String(256), nullable=False)
    finding_type: Mapped[str] = mapped_column(String(64), nullable=False)
    severity: Mapped[str] = mapped_column(String(16), default="warning")
    evidence: Mapped[dict] = mapped_column(JSONB, nullable=False)
    recommendation: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[ReviewStatus] = mapped_column(
        Enum(ReviewStatus, name="review_status", create_type=False),
        default=ReviewStatus.pending,
    )
    reviewed_by: Mapped[str | None] = mapped_column(String(128))
    review_notes: Mapped[str | None] = mapped_column(Text)
    auto_deploy_blocked: Mapped[bool] = mapped_column(Boolean, default=True)


class Alert(Base):
    __tablename__ = "alerts"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    agent_source: Mapped[str] = mapped_column(String(64), nullable=False)
    severity: Mapped[AlertSeverity] = mapped_column(
        Enum(AlertSeverity, name="alert_severity", create_type=False),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(256), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    alert_metadata: Mapped[dict] = mapped_column("metadata", JSONB, default=dict)
    acknowledged: Mapped[bool] = mapped_column(Boolean, default=False)
    telegram_sent: Mapped[bool] = mapped_column(Boolean, default=False)
    email_sent: Mapped[bool] = mapped_column(Boolean, default=False)


class CeoBriefing(Base):
    __tablename__ = "ceo_briefings"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    briefing_date: Mapped[date] = mapped_column(Date, unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    briefing_json: Mapped[dict] = mapped_column(JSONB, nullable=False)
    system_status: Mapped[str | None] = mapped_column(String(32))
    live_pnl: Mapped[Decimal | None] = mapped_column(Numeric(14, 4))
    risk_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    infra_health_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    active_alerts_count: Mapped[int] = mapped_column(Integer, default=0)
    pending_reviews: Mapped[int] = mapped_column(Integer, default=0)


class MarketingContentQueue(Base):
    __tablename__ = "marketing_content_queue"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    platform: Mapped[str] = mapped_column(String(32), nullable=False)
    content_type: Mapped[str] = mapped_column(String(32), default="post")
    pillar: Mapped[str | None] = mapped_column(String(64))
    title: Mapped[str | None] = mapped_column(String(256))
    body: Mapped[str] = mapped_column(Text, nullable=False)
    hashtags: Mapped[list] = mapped_column(ARRAY(Text), default=list)
    status: Mapped[str] = mapped_column(String(16), default="draft")
    scheduled_for: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[str] = mapped_column(String(64), default="marketing_agent")
    metadata: Mapped[dict] = mapped_column(JSONB, default=dict)


class MarketingTrendSignal(Base):
    __tablename__ = "marketing_trend_signals"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    topic: Mapped[str] = mapped_column(String(128), nullable=False)
    category: Mapped[str | None] = mapped_column(String(64))
    relevance_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 4))
    suggested_angle: Mapped[str | None] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(64), default="marketing_agent")
    acted_on: Mapped[bool] = mapped_column(Boolean, default=False)


class MarketingCycleReport(Base):
    __tablename__ = "marketing_cycle_reports"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    cycle_date: Mapped[date] = mapped_column(Date, unique=True, nullable=False)
    items_generated: Mapped[int] = mapped_column(Integer, default=0)
    trends_scanned: Mapped[int] = mapped_column(Integer, default=0)
    report_json: Mapped[dict] = mapped_column(JSONB, default=dict)
