"""Dashboard overview schema tests."""

from app.schemas.events import DashboardOverview


def test_dashboard_overview_includes_marketing_drafts() -> None:
    fields = DashboardOverview.model_fields
    assert "pending_marketing_drafts" in fields
    assert fields["pending_marketing_drafts"].default == 0


def test_dashboard_overview_parses_full_payload() -> None:
    data = DashboardOverview(
        bsv32_status="running",
        system_running=True,
        nfp_blackout=False,
        live_pnl=100.0,
        floating_pnl=100.0,
        daily_pnl=50.0,
        open_positions=1,
        risk_score=0.2,
        market_regime="ranging",
        infra_health_score=0.9,
        active_alerts=0,
        pending_reviews=1,
        pending_marketing_drafts=3,
        mt5_connected=True,
        last_updated="2026-05-28T12:00:00+00:00",
    )
    assert data.pending_marketing_drafts == 3
