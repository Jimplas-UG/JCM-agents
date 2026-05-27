"""Execution Quality Agent — broker and fill performance monitoring."""

from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.config import get_settings
from app.models.tables import ExecutionQualityLog, TradeEvent
from app.services.alerting import AlertService


class ExecutionQualityAgent(BaseAgent):
    name = "execution_quality"
    description = "Slippage, spread, fill speed, rejection rate monitoring"

    SLIPPAGE_ANOMALY_THRESHOLD = 2.0
    FILL_SPEED_ANOMALY_MS = 2000

    async def run_cycle(self) -> dict[str, Any]:
        analysis = await self.analyze_recent_execution()
        return {"status": "ok", **analysis}

    async def record_from_trade(self, trade: TradeEvent) -> ExecutionQualityLog:
        spread_ratio = None
        if trade.spread_at_entry and trade.spread_avg_24h:
            avg = float(trade.spread_avg_24h)
            spread_ratio = float(trade.spread_at_entry) / avg if avg > 0 else 1.0

        anomaly = False
        if trade.slippage_pips and float(trade.slippage_pips) > self.SLIPPAGE_ANOMALY_THRESHOLD:
            anomaly = True
        if trade.execution_latency_ms and trade.execution_latency_ms > self.FILL_SPEED_ANOMALY_MS:
            anomaly = True
        if spread_ratio and spread_ratio > 1.5:
            anomaly = True

        log = ExecutionQualityLog(
            trade_event_id=trade.id,
            symbol=trade.symbol,
            slippage_pips=trade.slippage_pips,
            spread_at_exec=trade.spread_at_entry,
            spread_avg=trade.spread_avg_24h,
            fill_speed_ms=trade.execution_latency_ms,
            anomaly_flag=anomaly,
        )
        self.db.add(log)
        await self.db.flush()

        if anomaly:
            await self._flag_anomaly(trade, log)
        return log

    async def analyze_recent_execution(self, hours: int = 24) -> dict[str, Any]:
        cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)
        result = await self.db.execute(
            select(ExecutionQualityLog).where(ExecutionQualityLog.created_at >= cutoff)
        )
        logs = list(result.scalars().all())

        if not logs:
            return {"sample_size": 0, "message": "no_execution_data"}

        slippages = [float(l.slippage_pips) for l in logs if l.slippage_pips]
        fill_speeds = [l.fill_speed_ms for l in logs if l.fill_speed_ms]
        rejections = sum(1 for l in logs if l.rejection)
        anomalies = sum(1 for l in logs if l.anomaly_flag)

        avg_slip = sum(slippages) / len(slippages) if slippages else 0
        avg_fill = sum(fill_speeds) / len(fill_speeds) if fill_speeds else 0
        rejection_rate = rejections / len(logs) if logs else 0

        trend = await self._slippage_trend()
        recommendation = None
        if trend.get("worsening"):
            recommendation = "Consider reducing trade frequency — slippage trending worse"
            await self._alert_degradation(avg_slip, trend)

        return {
            "sample_size": len(logs),
            "avg_slippage_pips": round(avg_slip, 4),
            "avg_fill_speed_ms": round(avg_fill, 1),
            "rejection_rate": round(rejection_rate, 4),
            "anomaly_count": anomalies,
            "slippage_trend": trend,
            "recommendation": recommendation,
        }

    async def _slippage_trend(self) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        recent = now - timedelta(hours=24)
        prior = now - timedelta(hours=48)

        recent_avg = await self.db.execute(
            select(func.avg(ExecutionQualityLog.slippage_pips)).where(
                ExecutionQualityLog.created_at >= recent
            )
        )
        prior_avg = await self.db.execute(
            select(func.avg(ExecutionQualityLog.slippage_pips)).where(
                and_(
                    ExecutionQualityLog.created_at >= prior,
                    ExecutionQualityLog.created_at < recent,
                )
            )
        )
        r = float(recent_avg.scalar() or 0)
        p = float(prior_avg.scalar() or 0)
        worsening = r > p * 1.2 if p > 0 else False
        return {
            "recent_avg": round(r, 4),
            "prior_avg": round(p, 4),
            "worsening": worsening,
        }

    async def _flag_anomaly(self, trade: TradeEvent, log: ExecutionQualityLog) -> None:
        alert_svc = AlertService(self.db)
        await alert_svc.create_alert(
            agent_source=self.name,
            severity="warning",
            title=f"Execution Anomaly — {trade.symbol}",
            message=(
                f"Slippage: {log.slippage_pips} pips, "
                f"Fill: {log.fill_speed_ms}ms"
            ),
            metadata={"trade_event_id": str(trade.event_id), "symbol": trade.symbol},
        )

    async def _alert_degradation(self, avg_slip: float, trend: dict) -> None:
        alert_svc = AlertService(self.db)
        await alert_svc.create_alert(
            agent_source=self.name,
            severity="warning",
            title="Broker Execution Degradation",
            message=f"Avg slippage {avg_slip:.2f} pips — trend worsening",
            metadata=trend,
        )
