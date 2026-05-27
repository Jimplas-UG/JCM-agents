-- =============================================================================
-- Jimplas Capital Management — BSv3.2 Supervisory Platform
-- PostgreSQL Schema (read-only observation of BSv3.2 engine events)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- ---------------------------------------------------------------------------
-- Enumerations
-- ---------------------------------------------------------------------------
CREATE TYPE trade_direction AS ENUM ('long', 'short');
CREATE TYPE trade_outcome AS ENUM ('win', 'loss', 'breakeven', 'open', 'cancelled');
CREATE TYPE market_regime AS ENUM (
    'trending_bull', 'trending_bear', 'ranging', 'volatile', 'low_vol', 'unknown'
);
CREATE TYPE trading_session AS ENUM (
    'london', 'new_york', 'overlap', 'off_session', 'asia'
);
CREATE TYPE event_type AS ENUM (
    'trade_executed', 'trade_blocked', 'trade_closed',
    'filter_state_change', 'risk_parameter_change',
    'kill_switch', 'confidence_shift', 'system_state'
);
CREATE TYPE bsv32_filter_name AS ENUM (
    'nfp_blackout', 'yield_filter', 'dxy_filter', 'ath_zone',
    'geopolitical', 'chop_zone', 'buy_path', 'risk_gating',
    'watchdog', 'multi_condition', 'execution_filter'
);
CREATE TYPE alert_severity AS ENUM ('info', 'warning', 'critical', 'emergency');
CREATE TYPE review_status AS ENUM ('pending', 'approved', 'rejected', 'deferred');

-- ---------------------------------------------------------------------------
-- BSv3.2 Trade Events (core time-series table)
-- ---------------------------------------------------------------------------
CREATE TABLE trade_events (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id            VARCHAR(64) UNIQUE NOT NULL,
    event_type          event_type NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    symbol              VARCHAR(16) NOT NULL,
    direction           trade_direction,
    lot_size            DECIMAL(10, 4),
    entry_price         DECIMAL(18, 6),
    exit_price          DECIMAL(18, 6),
    stop_loss           DECIMAL(18, 6),
    take_profit         DECIMAL(18, 6),
    requested_price     DECIMAL(18, 6),
    filled_price        DECIMAL(18, 6),
    slippage_pips       DECIMAL(10, 4),
    spread_at_entry     DECIMAL(10, 4),
    spread_avg_24h      DECIMAL(10, 4),
    execution_latency_ms INTEGER,
    pips                DECIMAL(10, 4),
    r_multiple          DECIMAL(10, 4),
    outcome             trade_outcome DEFAULT 'open',
    pnl_usd             DECIMAL(14, 4),
    -- BSv3.2 filter states at decision time (JSON: filter_name -> passed/blocked)
    filter_states       JSONB NOT NULL DEFAULT '{}',
    filters_passed      TEXT[] DEFAULT '{}',
    filters_blocked     TEXT[] DEFAULT '{}',
    -- Market context
    market_regime       market_regime DEFAULT 'unknown',
    trading_session     trading_session DEFAULT 'off_session',
    dxy_value           DECIMAL(10, 4),
    dxy_state           VARCHAR(32),
    yield_10y           DECIMAL(10, 4),
    yield_state         VARCHAR(32),
    volatility_state    VARCHAR(32),
    geopolitical_flag   BOOLEAN DEFAULT FALSE,
    ath_zone_active     BOOLEAN DEFAULT FALSE,
    chop_zone_active    BOOLEAN DEFAULT FALSE,
    nfp_blackout_active BOOLEAN DEFAULT FALSE,
    -- BSv3.2 metadata
    bsv32_confidence    DECIMAL(5, 4),
    bsv32_version       VARCHAR(16) DEFAULT '3.2',
    -- Infrastructure snapshot
    vps_cpu_pct         DECIMAL(5, 2),
    vps_ram_pct         DECIMAL(5, 2),
    vps_disk_pct        DECIMAL(5, 2),
    mt5_connected       BOOLEAN,
    -- Raw payload for audit
    raw_payload         JSONB
);

CREATE INDEX idx_trade_events_created_at ON trade_events (created_at DESC);
CREATE INDEX idx_trade_events_symbol ON trade_events (symbol, created_at DESC);
CREATE INDEX idx_trade_events_outcome ON trade_events (outcome, created_at DESC);
CREATE INDEX idx_trade_events_regime ON trade_events (market_regime, created_at DESC);
CREATE INDEX idx_trade_events_session ON trade_events (trading_session, created_at DESC);
CREATE INDEX idx_trade_events_filter_states ON trade_events USING GIN (filter_states);

-- ---------------------------------------------------------------------------
-- Filter Block Events (for false-positive analysis)
-- ---------------------------------------------------------------------------
CREATE TABLE filter_block_events (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id            VARCHAR(64) UNIQUE NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    symbol              VARCHAR(16) NOT NULL,
    direction           trade_direction,
    blocked_by          bsv32_filter_name[] NOT NULL,
    filter_states       JSONB NOT NULL DEFAULT '{}',
    market_regime       market_regime DEFAULT 'unknown',
    trading_session     trading_session DEFAULT 'off_session',
    dxy_state           VARCHAR(32),
    yield_state         VARCHAR(32),
    hypothetical_outcome trade_outcome,
    hypothetical_pips   DECIMAL(10, 4),
    counterfactual_evaluated BOOLEAN DEFAULT FALSE,
    raw_payload         JSONB
);

CREATE INDEX idx_filter_blocks_created_at ON filter_block_events (created_at DESC);
CREATE INDEX idx_filter_blocks_blocked_by ON filter_block_events USING GIN (blocked_by);

-- ---------------------------------------------------------------------------
-- System State Snapshots
-- ---------------------------------------------------------------------------
CREATE TABLE system_state_snapshots (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    bsv32_status        VARCHAR(32) NOT NULL,
    nfp_blackout        BOOLEAN DEFAULT FALSE,
    yield_filter_state  VARCHAR(32),
    dxy_filter_state    VARCHAR(32),
    ath_zone_active     BOOLEAN DEFAULT FALSE,
    geopolitical_active BOOLEAN DEFAULT FALSE,
    chop_zone_active    BOOLEAN DEFAULT FALSE,
    risk_gating_active  BOOLEAN DEFAULT FALSE,
    watchdog_ok         BOOLEAN DEFAULT TRUE,
    mt5_connected       BOOLEAN DEFAULT FALSE,
    desk_api_ok         BOOLEAN DEFAULT FALSE,
    forward_bot_ok      BOOLEAN DEFAULT FALSE,
    watchdog_api_ok     BOOLEAN DEFAULT FALSE,
    open_positions      INTEGER DEFAULT 0,
    account_equity      DECIMAL(14, 4),
    account_balance     DECIMAL(14, 4),
    floating_pnl        DECIMAL(14, 4),
    daily_pnl           DECIMAL(14, 4),
    drawdown_pct        DECIMAL(8, 4),
    market_regime       market_regime DEFAULT 'unknown',
    raw_snapshot        JSONB
);

CREATE INDEX idx_system_state_created_at ON system_state_snapshots (created_at DESC);

-- ---------------------------------------------------------------------------
-- Infrastructure Health Logs
-- ---------------------------------------------------------------------------
CREATE TABLE infra_health_logs (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    vps_cpu_pct         DECIMAL(5, 2),
    vps_ram_pct         DECIMAL(5, 2),
    vps_disk_pct        DECIMAL(5, 2),
    mt5_connected       BOOLEAN,
    mt5_latency_ms      INTEGER,
    desk_api_ok         BOOLEAN,
    desk_api_latency_ms INTEGER,
    forward_bot_ok      BOOLEAN,
    forward_bot_latency_ms INTEGER,
    watchdog_ok         BOOLEAN,
    network_ping_ms     INTEGER,
    execution_delay_ms  INTEGER,
    service_states      JSONB DEFAULT '{}',
    alert_triggered     BOOLEAN DEFAULT FALSE,
    remediation_action  VARCHAR(128)
);

CREATE INDEX idx_infra_health_created_at ON infra_health_logs (created_at DESC);

-- ---------------------------------------------------------------------------
-- Execution Quality Metrics
-- ---------------------------------------------------------------------------
CREATE TABLE execution_quality_logs (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trade_event_id      UUID REFERENCES trade_events(id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    symbol              VARCHAR(16) NOT NULL,
    slippage_pips       DECIMAL(10, 4),
    spread_at_exec      DECIMAL(10, 4),
    spread_avg          DECIMAL(10, 4),
    fill_speed_ms       INTEGER,
    rejection           BOOLEAN DEFAULT FALSE,
    rejection_reason    VARCHAR(256),
    mt5_timeout         BOOLEAN DEFAULT FALSE,
    mt5_freeze          BOOLEAN DEFAULT FALSE,
    anomaly_flag        BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_exec_quality_created_at ON execution_quality_logs (created_at DESC);
CREATE INDEX idx_exec_quality_symbol ON execution_quality_logs (symbol, created_at DESC);

-- ---------------------------------------------------------------------------
-- Risk Exposure Snapshots
-- ---------------------------------------------------------------------------
CREATE TABLE risk_exposure_snapshots (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    open_positions      INTEGER DEFAULT 0,
    total_exposure_lots DECIMAL(10, 4),
    correlated_pairs    JSONB DEFAULT '[]',
    correlation_risk_score DECIMAL(5, 4),
    account_drawdown_pct DECIMAL(8, 4),
    daily_drawdown_pct  DECIMAL(8, 4),
    risk_score          DECIMAL(5, 4),
    lot_scaling_factor  DECIMAL(5, 4) DEFAULT 1.0,
    kill_switch_recommended BOOLEAN DEFAULT FALSE,
    trade_frequency_1h  INTEGER DEFAULT 0,
    alerts              JSONB DEFAULT '[]'
);

CREATE INDEX idx_risk_exposure_created_at ON risk_exposure_snapshots (created_at DESC);

-- ---------------------------------------------------------------------------
-- Explainability Audit Trail
-- ---------------------------------------------------------------------------
CREATE TABLE audit_trail (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_type          event_type NOT NULL,
    reference_id        VARCHAR(64),
    summary             TEXT NOT NULL,
    explanation_json    JSONB NOT NULL,
    human_readable      TEXT,
    severity            alert_severity DEFAULT 'info'
);

CREATE INDEX idx_audit_trail_created_at ON audit_trail (created_at DESC);
CREATE INDEX idx_audit_trail_event_type ON audit_trail (event_type, created_at DESC);

-- ---------------------------------------------------------------------------
-- Performance Daily Aggregates
-- ---------------------------------------------------------------------------
CREATE TABLE performance_daily (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_date         DATE NOT NULL UNIQUE,
    total_trades        INTEGER DEFAULT 0,
    wins                INTEGER DEFAULT 0,
    losses              INTEGER DEFAULT 0,
    breakeven           INTEGER DEFAULT 0,
    win_rate            DECIMAL(5, 4),
    expectancy          DECIMAL(10, 4),
    avg_r_multiple      DECIMAL(10, 4),
    total_pips          DECIMAL(12, 4),
    total_pnl_usd       DECIMAL(14, 4),
    max_drawdown_pct    DECIMAL(8, 4),
    by_regime           JSONB DEFAULT '{}',
    by_session          JSONB DEFAULT '{}',
    by_dxy_state        JSONB DEFAULT '{}',
    by_yield_state      JSONB DEFAULT '{}',
    by_day_of_week      JSONB DEFAULT '{}',
    filter_efficiency   JSONB DEFAULT '{}',
    edge_decay_score    DECIMAL(5, 4),
    anomaly_flags       JSONB DEFAULT '[]',
    report_json         JSONB
);

CREATE INDEX idx_performance_daily_date ON performance_daily (report_date DESC);

-- ---------------------------------------------------------------------------
-- Research Review Queue (human-in-the-loop only)
-- ---------------------------------------------------------------------------
CREATE TABLE research_review_queue (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ,
    title               VARCHAR(256) NOT NULL,
    finding_type        VARCHAR(64) NOT NULL,
    severity            alert_severity DEFAULT 'warning',
    evidence            JSONB NOT NULL,
    recommendation    TEXT NOT NULL,
    status              review_status DEFAULT 'pending',
    reviewed_by         VARCHAR(128),
    review_notes        TEXT,
    auto_deploy_blocked BOOLEAN DEFAULT TRUE
);

CREATE INDEX idx_research_queue_status ON research_review_queue (status, created_at DESC);

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------
CREATE TABLE alerts (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ,
    agent_source        VARCHAR(64) NOT NULL,
    severity            alert_severity NOT NULL,
    title               VARCHAR(256) NOT NULL,
    message             TEXT NOT NULL,
    metadata            JSONB DEFAULT '{}',
    acknowledged        BOOLEAN DEFAULT FALSE,
    telegram_sent       BOOLEAN DEFAULT FALSE,
    email_sent          BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_alerts_created_at ON alerts (created_at DESC);
CREATE INDEX idx_alerts_unresolved ON alerts (acknowledged, created_at DESC)
    WHERE acknowledged = FALSE;

-- ---------------------------------------------------------------------------
-- CEO Daily Briefings
-- ---------------------------------------------------------------------------
CREATE TABLE ceo_briefings (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    briefing_date       DATE NOT NULL UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    briefing_json       JSONB NOT NULL,
    system_status       VARCHAR(32),
    live_pnl            DECIMAL(14, 4),
    risk_score          DECIMAL(5, 4),
    infra_health_score  DECIMAL(5, 4),
    active_alerts_count INTEGER DEFAULT 0,
    pending_reviews     INTEGER DEFAULT 0
);

CREATE INDEX idx_ceo_briefings_date ON ceo_briefings (briefing_date DESC);
