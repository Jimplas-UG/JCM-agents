"""Application configuration from environment variables."""

from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "JCM-BSv32-Platform"
    app_env: str = "production"
    app_debug: bool = False
    api_host: str = "0.0.0.0"
    api_port: int = 8000
    api_secret_key: str = "change-me"
    cors_origins: str = "http://localhost:3000"

    postgres_host: str = "localhost"
    postgres_port: int = 5432
    postgres_user: str = "jcm_admin"
    postgres_password: str = "changeme"
    postgres_db: str = "jcm_bsv32"
    database_url: str = ""

    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_password: str = ""
    redis_url: str = ""

    mt5_api_url: str = "http://localhost:8081"
    mt5_api_key: str = ""
    desk_api_url: str = "http://localhost:8082"
    desk_api_key: str = ""
    forward_bot_api_url: str = "http://localhost:8083"
    forward_bot_api_key: str = ""
    watchdog_api_url: str = "http://localhost:8084"
    watchdog_api_key: str = ""

    event_webhook_secret: str = ""
    event_ingestion_batch_size: int = 100

    vps_host: str = "localhost"
    infra_check_interval_seconds: int = 30
    infra_restart_max_retries: int = 3
    infra_backoff_base_seconds: int = 5

    telegram_bot_token: str = ""
    telegram_chat_id: str = ""
    alert_email_smtp_host: str = ""
    alert_email_smtp_port: int = 587
    alert_email_from: str = ""
    alert_email_to: str = ""
    alert_email_password: str = ""

    max_account_drawdown_pct: float = 5.0
    max_daily_drawdown_pct: float = 2.0
    max_concurrent_positions: int = 3
    correlation_threshold: float = 0.75
    trade_frequency_limit_per_hour: int = 6

    perf_report_cron: str = "0 0 * * *"
    edge_decay_lookback_days: int = 90
    anomaly_zscore_threshold: float = 2.5

    research_min_sample_size: int = 30
    research_drift_window_days: int = 30

    marketing_docs_path: str = "/app/docs"
    marketing_cycle_hours: int = 24
    marketing_auto_approve: bool = False

    prometheus_enabled: bool = True
    metrics_path: str = "/metrics"
    metrics_require_auth: bool = True
    rate_limit_per_minute: int = 120
    strict_security: bool = False
    log_level: str = "INFO"
    log_format: str = "json"

    @model_validator(mode="after")
    def assemble_connection_urls(self) -> "Settings":
        if not self.database_url or "${" in self.database_url:
            self.database_url = (
                f"postgresql+asyncpg://{self.postgres_user}:{self.postgres_password}"
                f"@{self.postgres_host}:{self.postgres_port}/{self.postgres_db}"
            )
        if not self.redis_url or "${" in self.redis_url:
            auth = f":{self.redis_password}@" if self.redis_password else ""
            self.redis_url = f"redis://{auth}{self.redis_host}:{self.redis_port}/0"
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def api_auth_required(self) -> bool:
        if self.app_env != "production":
            return False
        return self.api_secret_key not in ("", "change-me")

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"

    @property
    def metrics_auth_required(self) -> bool:
        if not self.prometheus_enabled or not self.metrics_require_auth:
            return False
        return self.is_production

    def validate_production_secrets(self) -> list[str]:
        issues: list[str] = []
        if not self.is_production:
            return issues
        if self.api_secret_key in ("", "change-me"):
            issues.append("API_SECRET_KEY must be set to a strong value in production")
        if not self.event_webhook_secret:
            issues.append("EVENT_WEBHOOK_SECRET must be set in production")
        if self.postgres_password in ("", "changeme"):
            issues.append("POSTGRES_PASSWORD must not use default in production")
        return issues


@lru_cache
def get_settings() -> Settings:
    return Settings()
