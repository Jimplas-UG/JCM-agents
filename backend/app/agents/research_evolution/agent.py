"""Research Evolution Agent — autonomous monitoring, human review queue only."""

from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.config import get_settings
from app.models.tables import (
    AlertSeverity,
    ExecutionQualityLog,
    FilterBlockEvent,
    ResearchReviewQueue,
    ReviewStatus,
    TradeEvent,
)
from app.utils.enums import coerce_enum


class ResearchEvolutionAgent(BaseAgent):
    name = "research_evolution"
    description = "Detects drift, regime shifts, filter alpha — recommendations to human queue only"

    async def run_cycle(self) -> dict[str, Any]:
        findings = []
        findings.extend(await self._detect_filter_drift())
        findings.extend(await self._detect_regime_shift())
        findings.extend(await self._analyze_filter_combinations())
        findings.extend(await self._detect_execution_degradation())

        queued = 0
        for finding in findings:
            await self._queue_for_review(finding)
            queued += 1

        return {"status": "ok", "findings_queued": queued}

    async def _detect_filter_drift(self) -> list[dict[str, Any]]:
        settings = get_settings()
        window = settings.research_drift_window_days
        cutoff = datetime.now(timezone.utc) - timedelta(days=window)
        mid = cutoff + timedelta(days=window // 2)

        findings = []
        filters = [
            "nfp_blackout", "yield_filter", "dxy_filter", "ath_zone",
            "geopolitical", "chop_zone", "buy_path",
        ]

        for filt in filters:
            early = await self._filter_block_rate(filt, cutoff, mid)
            late = await self._filter_block_rate(filt, mid, datetime.now(timezone.utc))
            if early > 0 and late > early * 1.5:
                findings.append({
                    "title": f"Filter drift detected: {filt}",
                    "finding_type": "filter_drift",
                    "severity": "warning",
                    "evidence": {
                        "filter": filt,
                        "early_block_rate": round(early, 4),
                        "late_block_rate": round(late, 4),
                        "window_days": window,
                    },
                    "recommendation": (
                        f"Review {filt} effectiveness — block rate increased "
                        f"{round((late - early) / early * 100, 1)}% over rolling window. "
                        "Human review required. No auto-deploy."
                    ),
                })
        return findings

    async def _filter_block_rate(
        self, filter_name: str, start: datetime, end: datetime
    ) -> float:
        total_result = await self.db.execute(
            select(func.count(FilterBlockEvent.id)).where(
                and_(
                    FilterBlockEvent.created_at >= start,
                    FilterBlockEvent.created_at < end,
                )
            )
        )
        total = total_result.scalar() or 0
        if total < get_settings().research_min_sample_size // 3:
            return 0.0

        blocked_result = await self.db.execute(
            select(func.count(FilterBlockEvent.id)).where(
                and_(
                    FilterBlockEvent.created_at >= start,
                    FilterBlockEvent.created_at < end,
                    FilterBlockEvent.blocked_by.contains([filter_name]),
                )
            )
        )
        blocked = blocked_result.scalar() or 0
        return blocked / total if total else 0.0

    async def _detect_regime_shift(self) -> list[dict[str, Any]]:
        cutoff = datetime.now(timezone.utc) - timedelta(days=14)
        result = await self.db.execute(
            select(TradeEvent.market_regime, func.count(TradeEvent.id))
            .where(TradeEvent.created_at >= cutoff)
            .group_by(TradeEvent.market_regime)
        )
        distribution = {row[0]: row[1] for row in result.all()}
        if not distribution:
            return []

        dominant = max(distribution, key=distribution.get)
        total = sum(distribution.values())
        dominant_pct = distribution[dominant] / total

        if dominant_pct > 0.7 and dominant in ("ranging", "volatile"):
            return [{
                "title": f"Regime concentration: {dominant}",
                "finding_type": "regime_shift",
                "severity": "info",
                "evidence": {
                    "distribution": distribution,
                    "dominant_regime": dominant,
                    "dominant_pct": round(dominant_pct, 4),
                },
                "recommendation": (
                    f"Market has been {dominant_pct:.0%} {dominant} over 14 days. "
                    "BSv3.2 edge may be affected — review strategy performance in this regime."
                ),
            }]
        return []

    async def _analyze_filter_combinations(self) -> list[dict[str, Any]]:
        cutoff = datetime.now(timezone.utc) - timedelta(days=30)
        result = await self.db.execute(
            select(FilterBlockEvent.blocked_by, func.count(FilterBlockEvent.id))
            .where(FilterBlockEvent.created_at >= cutoff)
            .group_by(FilterBlockEvent.blocked_by)
            .order_by(func.count(FilterBlockEvent.id).desc())
            .limit(5)
        )
        combos = [
            {"combination": list(row[0]), "block_count": row[1]}
            for row in result.all()
        ]
        if not combos:
            return []

        top = combos[0]
        if top["block_count"] >= get_settings().research_min_sample_size:
            return [{
                "title": "High-friction filter combination identified",
                "finding_type": "filter_combination",
                "severity": "info",
                "evidence": {"top_combinations": combos},
                "recommendation": (
                    f"Filter combo {top['combination']} blocked {top['block_count']} "
                    "signals in 30 days. Evaluate alpha vs friction tradeoff."
                ),
            }]
        return []

    async def _detect_execution_degradation(self) -> list[dict[str, Any]]:
        recent = datetime.now(timezone.utc) - timedelta(days=7)
        prior_start = datetime.now(timezone.utc) - timedelta(days=14)

        recent_avg = await self.db.execute(
            select(func.avg(ExecutionQualityLog.slippage_pips)).where(
                ExecutionQualityLog.created_at >= recent
            )
        )
        prior_avg = await self.db.execute(
            select(func.avg(ExecutionQualityLog.slippage_pips)).where(
                and_(
                    ExecutionQualityLog.created_at >= prior_start,
                    ExecutionQualityLog.created_at < recent,
                )
            )
        )
        r = float(recent_avg.scalar() or 0)
        p = float(prior_avg.scalar() or 0)

        if p > 0 and r > p * 1.3:
            return [{
                "title": "Market microstructure execution degradation",
                "finding_type": "execution_degradation",
                "severity": "warning",
                "evidence": {
                    "recent_avg_slippage": round(r, 4),
                    "prior_avg_slippage": round(p, 4),
                    "pct_increase": round((r - p) / p * 100, 1),
                },
                "recommendation": (
                    "Execution quality degrading — possible broker or microstructure change. "
                    "Review broker settings and consider frequency reduction."
                ),
            }]
        return []

    async def _queue_for_review(self, finding: dict[str, Any]) -> ResearchReviewQueue:
        existing = await self.db.execute(
            select(ResearchReviewQueue).where(
                ResearchReviewQueue.title == finding["title"],
                ResearchReviewQueue.finding_type == finding["finding_type"],
                ResearchReviewQueue.status == ReviewStatus.pending,
            ).limit(1)
        )
        dup = existing.scalar_one_or_none()
        if dup:
            return dup

        entry = ResearchReviewQueue(
            title=finding["title"],
            finding_type=finding["finding_type"],
            severity=coerce_enum(
                AlertSeverity, finding.get("severity", "info"), AlertSeverity.info
            ),
            evidence=finding["evidence"],
            recommendation=finding["recommendation"],
            status=ReviewStatus.pending,
            auto_deploy_blocked=True,
        )
        self.db.add(entry)
        await self.db.flush()
        self.logger.info("research_queued", title=finding["title"])
        return entry
