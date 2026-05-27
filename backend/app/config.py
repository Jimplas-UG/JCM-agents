"""Application configuration from environment variables."""

from functools import lru_cache

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

    database_url: str = (
        "postgresql+asyncpg://jcm_admin:changeme@localhost:5432/jcm_bsv32"
    )
    redis_url: str = "redis://localhost:6379/0"

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

    prometheus_enabled: bool = True
    metrics_path: str = "/metrics"
    log_level: str = "INFO"
    log_format: str = "json"

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
