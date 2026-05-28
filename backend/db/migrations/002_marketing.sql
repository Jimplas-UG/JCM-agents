-- Marketing Agent tables (JCM brand & content operations)

CREATE TABLE marketing_content_queue (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ,
    platform        VARCHAR(32) NOT NULL,
    content_type    VARCHAR(32) NOT NULL DEFAULT 'post',
    pillar          VARCHAR(64),
    title           VARCHAR(256),
    body            TEXT NOT NULL,
    hashtags        TEXT[] DEFAULT '{}',
    status          VARCHAR(16) NOT NULL DEFAULT 'draft',
    scheduled_for   TIMESTAMPTZ,
    published_at    TIMESTAMPTZ,
    created_by      VARCHAR(64) DEFAULT 'marketing_agent',
    metadata        JSONB DEFAULT '{}'
);

CREATE INDEX idx_marketing_content_status ON marketing_content_queue (status, created_at DESC);
CREATE INDEX idx_marketing_content_platform ON marketing_content_queue (platform, scheduled_for);
CREATE INDEX idx_marketing_content_scheduled ON marketing_content_queue (scheduled_for)
    WHERE status IN ('draft', 'approved');

CREATE TABLE marketing_trend_signals (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    topic           VARCHAR(128) NOT NULL,
    category        VARCHAR(64),
    relevance_score DECIMAL(5, 4) DEFAULT 0.5,
    suggested_angle TEXT,
    source          VARCHAR(64) DEFAULT 'agent',
    acted_on        BOOLEAN DEFAULT FALSE
);

CREATE INDEX idx_marketing_trends_created ON marketing_trend_signals (created_at DESC);

CREATE TABLE marketing_cycle_reports (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cycle_date      DATE NOT NULL UNIQUE,
    items_generated INTEGER DEFAULT 0,
    trends_scanned  INTEGER DEFAULT 0,
    report_json     JSONB NOT NULL DEFAULT '{}'
);

CREATE INDEX idx_marketing_reports_date ON marketing_cycle_reports (cycle_date DESC);
