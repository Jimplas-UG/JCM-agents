"""Portfolio Risk Orchestrator — capital protection above BSv3.2 risk gating."""

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.config import get_settings
from app.db.redis_client import cache_set
from app.models.tables import RiskExposureSnapshot, SystemStateSnapshot, TradeEvent
from app.services.alerting import AlertService


class PortfolioRiskOrchestrator(BaseAgent):
    name = "portfolio_risk"
    description = "Exposure monitoring, correlation risk, lot scaling recommendations (informational)"

    CORRELATION_MATRIX: dict[tuple[str, str], float] = {
        ("EURUSD", "GBPUSD"): 0.85,
        ("EURUSD", "AUDUSD"): 0.72,
        ("GBPUSD", "AUDUSD"): 0.68,
        ("XAUUSD", "EURUSD"): -0.45,
        ("USDJPY", "EURUSD"): -0.62,
    }

    async def run_cycle(self) -> dict[str, Any]:
        snapshot = await self.assess_risk()
        await self._publish_lot_scaling(snapshot)
        return {"status": "ok", "risk_score": float(snapshot.risk_score or 0)}

    async def assess_risk(self) -> RiskExposureSnapshot:
        settings = get_settings()
        state = await self._latest_system_state()
        open_trades = await self._open_positions()

        exposure_lots = sum(float(t.lot_size or 0) for t in open_trades)
        correlated = self._detect_correlations(open_trades)
        corr_score = self._correlation_risk_score(correlated)

        account_dd = float(state.drawdown_pct or 0) if state else 0
        daily_dd = await self._daily_drawdown()
        freq_1h = await self._trade_frequency_1h()

        risk_score = self._compute_risk_score(
            account_dd, daily_dd, corr_score, len(open_trades), freq_1h
        )
        lot_scaling = self._lot_scaling_factor(risk_score, state)
        kill_switch = (
            account_dd >= settings.max_account_drawdown_pct
            or daily_dd >= settings.max_daily_drawdown_pct
        )

        alerts_list = []
        if kill_switch:
            alerts_list.append({
                "type": "kill_switch_recommended",
                "message": "Drawdown threshold breached — human action required",
                "severity": "emergency",
            })
        if freq_1h >= settings.trade_frequency_limit_per_hour:
            alerts_list.append({
                "type": "trade_frequency_limit",
                "message": f"Trade frequency {freq_1h}/hr exceeds limit",
                "severity": "warning",
            })

        snapshot = RiskExposureSnapshot(
            open_positions=len(open_trades),
            total_exposure_lots=Decimal(str(round(exposure_lots, 4))),
            correlated_pairs=correlated,
            correlation_risk_score=Decimal(str(round(corr_score, 4))),
            account_drawdown_pct=Decimal(str(round(account_dd, 4))),
            daily_drawdown_pct=Decimal(str(round(daily_dd, 4))),
            risk_score=Decimal(str(round(risk_score, 4))),
            lot_scaling_factor=Decimal(str(round(lot_scaling, 4))),
            kill_switch_recommended=kill_switch,
            trade_frequency_1h=freq_1h,
            alerts=alerts_list,
        )
        self.db.add(snapshot)
        await self.db.flush()

        if kill_switch:
            alert_svc = AlertService(self.db)
            await alert_svc.create_alert(
                agent_source=self.name,
                severity="emergency",
                title="Kill-Switch Recommended",
                message="Account drawdown threshold breached. Human intervention required.",
                metadata={"account_dd": account_dd, "daily_dd": daily_dd},
            )

        return snapshot

    async def _latest_system_state(self) -> SystemStateSnapshot | None:
        result = await self.db.execute(
            select(SystemStateSnapshot)
            .order_by(SystemStateSnapshot.created_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def _open_positions(self) -> list[TradeEvent]:
        result = await self.db.execute(
            select(TradeEvent).where(TradeEvent.outcome == "open")
        )
        return list(result.scalars().all())

    def _detect_correlations(self, trades: list[TradeEvent]) -> list[dict]:
        symbols = [t.symbol for t in trades]
        pairs = []
        for i, s1 in enumerate(symbols):
            for s2 in symbols[i + 1 :]:
                corr = self.CORRELATION_MATRIX.get((s1, s2)) or self.CORRELATION_MATRIX.get(
                    (s2, s1)
                )
                if corr and abs(corr) >= get_settings().correlation_threshold:
                    pairs.append({"pair": [s1, s2], "correlation": corr})
        return pairs

    def _correlation_risk_score(self, correlated: list[dict]) -> float:
        if not correlated:
            return 0.0
        return min(1.0, sum(abs(p["correlation"]) for p in correlated) / len(correlated))

    async def _daily_drawdown(self) -> float:
        today_start = datetime.now(timezone.utc).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        result = await self.db.execute(
            select(func.sum(TradeEvent.pnl_usd)).where(
                and_(
                    TradeEvent.created_at >= today_start,
                    TradeEvent.pnl_usd.isnot(None),
                )
            )
        )
        daily_pnl = float(result.scalar() or 0)
        state = await self._latest_system_state()
        balance = float(state.account_balance or 100000) if state else 100000
        return abs(min(0, daily_pnl)) / balance * 100 if balance else 0

    async def _trade_frequency_1h(self) -> int:
        one_hour_ago = datetime.now(timezone.utc) - timedelta(hours=1)
        result = await self.db.execute(
            select(func.count(TradeEvent.id)).where(
                TradeEvent.created_at >= one_hour_ago
            )
        )
        return result.scalar() or 0

    def _compute_risk_score(
        self,
        account_dd: float,
        daily_dd: float,
        corr_score: float,
        open_count: int,
        freq_1h: int,
    ) -> float:
        settings = get_settings()
        dd_component = min(1.0, account_dd / settings.max_account_drawdown_pct) * 0.4
        daily_component = min(1.0, daily_dd / settings.max_daily_drawdown_pct) * 0.25
        corr_component = corr_score * 0.2
        pos_component = (
            min(1.0, open_count / settings.max_concurrent_positions) * 0.1
        )
        freq_component = (
            min(1.0, freq_1h / settings.trade_frequency_limit_per_hour) * 0.05
        )
        return min(1.0, dd_component + daily_component + corr_component + pos_component + freq_component)

    def _lot_scaling_factor(
        self, risk_score: float, state: SystemStateSnapshot | None
    ) -> float:
        """Informational lot scaling recommendation — passed to BSv3.2 as input, never override."""
        base = 1.0 - (risk_score * 0.5)
        if state and state.market_regime in ("volatile", "low_vol"):
            base *= 0.85
        return max(0.25, min(1.0, round(base, 4)))

    async def _publish_lot_scaling(self, snapshot: RiskExposureSnapshot) -> None:
        import json

        payload = json.dumps({
            "lot_scaling_factor": float(snapshot.lot_scaling_factor),
            "risk_score": float(snapshot.risk_score or 0),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "note": "informational_input_only_not_override",
        })
        await cache_set("jcm:bsv32:lot_scaling", payload, ttl=120)
