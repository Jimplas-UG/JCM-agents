"""Performance Intelligence Agent — BSv3.2 strategy behaviour analytics."""

import json
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from typing import Any

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.config import get_settings
from app.models.tables import FilterBlockEvent, PerformanceDaily, TradeEvent


class PerformanceIntelligenceAgent(BaseAgent):
    name = "performance_intel"
    description = "Quant analyst for BSv3.2 win rate, expectancy, filter efficiency, edge decay"

    REPORTS_DIR = Path("/app/reports")

    async def run_cycle(self) -> dict[str, Any]:
        report = await self.generate_daily_report()
        return {"status": "ok", "report_date": str(report.get("report_date"))}

    async def generate_daily_report(self, target_date: date | None = None) -> dict[str, Any]:
        target = target_date or date.today()
        start = datetime.combine(target, datetime.min.time(), tzinfo=timezone.utc)
        end = start + timedelta(days=1)

        trades = await self._fetch_closed_trades(start, end)
        blocks = await self._fetch_blocks(start, end)

        metrics = self._compute_metrics(trades)
        segmented = self._segment_analysis(trades)
        filter_eff = await self._filter_efficiency(blocks, trades)
        edge_decay = await self._edge_decay_score()
        anomalies = self._detect_anomalies(trades, metrics)
        drawdown = self._drawdown_analysis(trades)

        report = {
            "report_date": str(target),
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "metrics": metrics,
            "segmented": segmented,
            "filter_efficiency": filter_eff,
            "edge_decay_score": edge_decay,
            "drawdown": drawdown,
            "anomaly_flags": anomalies,
            "slippage_correlation": self._slippage_outcome_correlation(trades),
        }

        await self._persist_daily(target, report)
        await self._write_json_report(target, report)
        return report

    async def _fetch_closed_trades(self, start: datetime, end: datetime) -> list[TradeEvent]:
        result = await self.db.execute(
            select(TradeEvent).where(
                and_(
                    TradeEvent.created_at >= start,
                    TradeEvent.created_at < end,
                    TradeEvent.outcome.in_(["win", "loss", "breakeven"]),
                )
            )
        )
        return list(result.scalars().all())

    async def _fetch_blocks(self, start: datetime, end: datetime) -> list[FilterBlockEvent]:
        result = await self.db.execute(
            select(FilterBlockEvent).where(
                and_(
                    FilterBlockEvent.created_at >= start,
                    FilterBlockEvent.created_at < end,
                )
            )
        )
        return list(result.scalars().all())

    def _compute_metrics(self, trades: list[TradeEvent]) -> dict[str, Any]:
        if not trades:
            return {"total_trades": 0, "win_rate": 0, "expectancy": 0, "avg_r_multiple": 0}

        wins = sum(1 for t in trades if t.outcome == "win")
        losses = sum(1 for t in trades if t.outcome == "loss")
        total = len(trades)
        win_rate = wins / total if total else 0

        r_values = [float(t.r_multiple) for t in trades if t.r_multiple is not None]
        pnl_values = [float(t.pnl_usd) for t in trades if t.pnl_usd is not None]

        avg_r = sum(r_values) / len(r_values) if r_values else 0
        expectancy = sum(pnl_values) / len(pnl_values) if pnl_values else 0

        return {
            "total_trades": total,
            "wins": wins,
            "losses": losses,
            "breakeven": total - wins - losses,
            "win_rate": round(win_rate, 4),
            "expectancy": round(expectancy, 4),
            "avg_r_multiple": round(avg_r, 4),
            "total_pips": round(sum(float(t.pips or 0) for t in trades), 2),
            "total_pnl_usd": round(sum(pnl_values), 2),
        }

    def _segment_analysis(self, trades: list[TradeEvent]) -> dict[str, dict]:
        segments = {
            "by_regime": defaultdict(lambda: {"wins": 0, "total": 0}),
            "by_session": defaultdict(lambda: {"wins": 0, "total": 0}),
            "by_dxy_state": defaultdict(lambda: {"wins": 0, "total": 0}),
            "by_yield_state": defaultdict(lambda: {"wins": 0, "total": 0}),
            "by_day_of_week": defaultdict(lambda: {"wins": 0, "total": 0}),
        }

        for t in trades:
            is_win = t.outcome == "win"
            for key, attr in [
                ("by_regime", t.market_regime),
                ("by_session", t.trading_session),
                ("by_dxy_state", t.dxy_state or "unknown"),
                ("by_yield_state", t.yield_state or "unknown"),
                ("by_day_of_week", t.created_at.strftime("%A") if t.created_at else "unknown"),
            ]:
                bucket = segments[key][attr]
                bucket["total"] += 1
                if is_win:
                    bucket["wins"] += 1

        return {
            k: {
                name: {
                    "win_rate": round(v["wins"] / v["total"], 4) if v["total"] else 0,
                    "total": v["total"],
                }
                for name, v in buckets.items()
            }
            for k, buckets in segments.items()
        }

    async def _filter_efficiency(
        self, blocks: list[FilterBlockEvent], trades: list[TradeEvent]
    ) -> dict[str, Any]:
        filter_stats: dict[str, dict] = defaultdict(
            lambda: {"blocks": 0, "saved_losses": 0, "false_positives": 0}
        )

        for b in blocks:
            for f in b.blocked_by or []:
                filter_stats[f]["blocks"] += 1
                if b.hypothetical_outcome == "loss":
                    filter_stats[f]["saved_losses"] += 1
                elif b.hypothetical_outcome == "win":
                    filter_stats[f]["false_positives"] += 1

        return dict(filter_stats)

    async def _edge_decay_score(self) -> float:
        settings = get_settings()
        lookback = settings.edge_decay_lookback_days
        cutoff = datetime.now(timezone.utc) - timedelta(days=lookback)
        mid = cutoff + timedelta(days=lookback // 2)

        early_result = await self.db.execute(
            select(func.avg(TradeEvent.r_multiple)).where(
                and_(
                    TradeEvent.created_at >= cutoff,
                    TradeEvent.created_at < mid,
                    TradeEvent.outcome.in_(["win", "loss"]),
                )
            )
        )
        late_result = await self.db.execute(
            select(func.avg(TradeEvent.r_multiple)).where(
                and_(
                    TradeEvent.created_at >= mid,
                    TradeEvent.outcome.in_(["win", "loss"]),
                )
            )
        )
        early = float(early_result.scalar() or 0)
        late = float(late_result.scalar() or 0)
        if early == 0:
            return 0.0
        decay = (early - late) / abs(early)
        return round(max(0, min(1, decay)), 4)

    def _detect_anomalies(self, trades: list[TradeEvent], metrics: dict) -> list[str]:
        flags = []
        settings = get_settings()
        if metrics.get("win_rate", 0) < 0.35 and metrics.get("total_trades", 0) >= 5:
            flags.append("low_win_rate_anomaly")
        if metrics.get("expectancy", 0) < 0 and metrics.get("total_trades", 0) >= 5:
            flags.append("negative_expectancy_anomaly")

        slippages = [float(t.slippage_pips) for t in trades if t.slippage_pips]
        if slippages:
            avg_slip = sum(slippages) / len(slippages)
            if avg_slip > settings.anomaly_zscore_threshold:
                flags.append("elevated_slippage_anomaly")
        return flags

    def _drawdown_analysis(self, trades: list[TradeEvent]) -> dict[str, Any]:
        equity = 0.0
        peak = 0.0
        max_dd = 0.0
        for t in sorted(trades, key=lambda x: x.created_at or datetime.min.replace(tzinfo=timezone.utc)):
            equity += float(t.pnl_usd or 0)
            peak = max(peak, equity)
            dd = (peak - equity) / peak if peak > 0 else 0
            max_dd = max(max_dd, dd)
        return {"max_drawdown_pct": round(max_dd * 100, 2), "current_equity": round(equity, 2)}

    def _slippage_outcome_correlation(self, trades: list[TradeEvent]) -> dict[str, Any]:
        pairs = [
            (float(t.slippage_pips), 1 if t.outcome == "win" else 0)
            for t in trades
            if t.slippage_pips is not None
        ]
        if len(pairs) < 3:
            return {"correlation": None, "sample_size": len(pairs)}
        slips, outcomes = zip(*pairs)
        n = len(slips)
        mean_s = sum(slips) / n
        mean_o = sum(outcomes) / n
        cov = sum((s - mean_s) * (o - mean_o) for s, o in pairs) / n
        std_s = (sum((s - mean_s) ** 2 for s in slips) / n) ** 0.5
        std_o = (sum((o - mean_o) ** 2 for o in outcomes) / n) ** 0.5
        corr = cov / (std_s * std_o) if std_s and std_o else 0
        return {"correlation": round(corr, 4), "sample_size": n}

    async def _persist_daily(self, target: date, report: dict) -> None:
        metrics = report["metrics"]
        existing = await self.db.execute(
            select(PerformanceDaily).where(PerformanceDaily.report_date == target)
        )
        row = existing.scalar_one_or_none()
        if row is None:
            row = PerformanceDaily(report_date=target)
            self.db.add(row)

        row.total_trades = metrics.get("total_trades", 0)
        row.wins = metrics.get("wins", 0)
        row.losses = metrics.get("losses", 0)
        row.breakeven = metrics.get("breakeven", 0)
        row.win_rate = Decimal(str(metrics.get("win_rate", 0)))
        row.expectancy = Decimal(str(metrics.get("expectancy", 0)))
        row.avg_r_multiple = Decimal(str(metrics.get("avg_r_multiple", 0)))
        row.total_pips = Decimal(str(metrics.get("total_pips", 0)))
        row.total_pnl_usd = Decimal(str(metrics.get("total_pnl_usd", 0)))
        row.max_drawdown_pct = Decimal(str(report["drawdown"].get("max_drawdown_pct", 0)))
        row.by_regime = report["segmented"].get("by_regime", {})
        row.by_session = report["segmented"].get("by_session", {})
        row.by_dxy_state = report["segmented"].get("by_dxy_state", {})
        row.by_yield_state = report["segmented"].get("by_yield_state", {})
        row.by_day_of_week = report["segmented"].get("by_day_of_week", {})
        row.filter_efficiency = report.get("filter_efficiency", {})
        row.edge_decay_score = Decimal(str(report.get("edge_decay_score", 0)))
        row.anomaly_flags = report.get("anomaly_flags", [])
        row.report_json = report
        await self.db.flush()

    async def _write_json_report(self, target: date, report: dict) -> None:
        self.REPORTS_DIR.mkdir(parents=True, exist_ok=True)
        path = self.REPORTS_DIR / f"daily_perf_{target}.json"
        path.write_text(json.dumps(report, indent=2, default=str))
