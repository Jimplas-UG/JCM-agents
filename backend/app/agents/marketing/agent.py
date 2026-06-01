"""Marketing Agent — JCM brand growth, content, and trend intelligence."""

import json
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.agents.marketing.brand_kit import TREND_TOPICS, validate_content
from app.agents.marketing.content_engine import ContentEngine
from app.config import get_settings
from app.db.redis_client import CHANNEL_DASHBOARD, publish
from app.metrics.prometheus import MARKETING_CONTENT_QUEUE
from app.models.tables import MarketingContentQueue, MarketingCycleReport, MarketingTrendSignal


class MarketingAgent(BaseAgent):
    """
    Official JCM marketing agent.

    Generates educational brand content only — never trading signals or return claims.
    All drafts enter human review queue (status=draft) unless explicitly approved.
    """

    name = "marketing_agent"
    description = "Brand authority, content generation, trend signals, social queue"

    def __init__(self, db: AsyncSession):
        super().__init__(db)
        self.engine = ContentEngine()

    async def run_cycle(self) -> dict[str, Any]:
        today = date.today()
        purged = await self.purge_stale_marketing_data(today)
        trends = await self.scan_trends()
        generated = await self.generate_and_queue_daily(today, purge_first=False)
        report = await self._persist_cycle_report(trends, generated)

        await publish(
            CHANNEL_DASHBOARD,
            json.dumps({
                "type": "marketing_cycle_complete",
                "items_generated": len(generated),
                "trends": len(trends),
                "purged": purged,
            }),
        )

        return {
            "status": "ok",
            "items_generated": len(generated),
            "trends_scanned": len(trends),
            "report_date": str(report.cycle_date),
            "purged": purged,
        }

    async def purge_stale_marketing_data(self, today: date | None = None) -> dict[str, int]:
        """Clear yesterday's drafts, trend log, and cycle reports before today's batch."""
        today = today or date.today()
        start_today = datetime.combine(today, datetime.min.time(), tzinfo=timezone.utc)

        drafts = await self.db.execute(
            delete(MarketingContentQueue).where(
                MarketingContentQueue.status == "draft",
                MarketingContentQueue.created_at < start_today,
            )
        )
        trends = await self.db.execute(
            delete(MarketingTrendSignal).where(MarketingTrendSignal.created_at < start_today)
        )
        reports = await self.db.execute(
            delete(MarketingCycleReport).where(MarketingCycleReport.cycle_date < today)
        )

        counts = {
            "drafts_removed": drafts.rowcount or 0,
            "trends_removed": trends.rowcount or 0,
            "reports_removed": reports.rowcount or 0,
        }
        self.logger.info("marketing_stale_purged", **counts, cycle_date=str(today))
        return counts

    async def _already_queued_cycle_key(self, cycle_key: str) -> bool:
        result = await self.db.execute(
            select(MarketingContentQueue.id).where(
                MarketingContentQueue.content_metadata["cycle_key"].as_string() == cycle_key
            ).limit(1)
        )
        return result.scalar_one_or_none() is not None

    async def _queue_batch_items(self, batch: list[dict]) -> list[MarketingContentQueue]:
        rows: list[MarketingContentQueue] = []

        for item in batch:
            cycle_key = (item.get("metadata") or {}).get("cycle_key")
            if cycle_key and await self._already_queued_cycle_key(cycle_key):
                continue

            existing = await self.db.execute(
                select(MarketingContentQueue).where(
                    MarketingContentQueue.title == item["title"],
                    MarketingContentQueue.platform == item["platform"],
                    MarketingContentQueue.status == "draft",
                )
            )
            if existing.scalar_one_or_none():
                continue

            scheduled = item.get("scheduled_for")
            scheduled_dt = None
            if scheduled:
                scheduled_dt = datetime.fromisoformat(scheduled.replace("Z", "+00:00"))

            row = MarketingContentQueue(
                platform=item["platform"],
                content_type=item.get("content_type", "post"),
                pillar=item.get("pillar"),
                title=item.get("title"),
                body=item["body"],
                hashtags=item.get("hashtags", []),
                status="draft",
                scheduled_for=scheduled_dt,
                content_metadata={
                    "compliance_warnings": item.get("compliance_warnings", []),
                    **item.get("metadata", {}),
                },
            )
            self.db.add(row)
            rows.append(row)

        settings = get_settings()
        if settings.marketing_auto_approve:
            for row in rows:
                row.status = "approved"
                row.content_metadata = {
                    **(row.content_metadata or {}),
                    "approved_by": "marketing_auto_approve",
                }

        await self.db.flush()
        self.logger.info("marketing_content_queued", count=len(rows))
        return rows

    async def generate_and_queue_daily(
        self,
        cycle_date: date | None = None,
        *,
        purge_first: bool = True,
    ) -> list[MarketingContentQueue]:
        """Queue 12 daily drafts (3 article, 3 LinkedIn, 3 X, 3 Instagram); idempotent per cycle_key."""
        d = cycle_date or date.today()
        if purge_first:
            await self.purge_stale_marketing_data(d)
        batch = self.engine.generate_daily_batch(d)
        return await self._queue_batch_items(batch)

    async def generate_and_queue_weekly(self) -> list[MarketingContentQueue]:
        batch = self.engine.generate_weekly_batch()
        return await self._queue_batch_items(batch)

    async def scan_trends(self) -> list[MarketingTrendSignal]:
        signals: list[MarketingTrendSignal] = []
        for t in TREND_TOPICS:
            result = await self.db.execute(
                select(MarketingTrendSignal)
                .where(MarketingTrendSignal.topic == t["topic"])
                .where(MarketingTrendSignal.created_at >= datetime.now(timezone.utc).replace(hour=0, minute=0, second=0))
            )
            if result.scalar_one_or_none():
                continue

            signal = MarketingTrendSignal(
                topic=t["topic"],
                category=t.get("category"),
                relevance_score=t.get("score", 0.5),
                suggested_angle=self._angle_for_topic(t["topic"]),
                source="marketing_agent",
            )
            self.db.add(signal)
            signals.append(signal)

        await self.db.flush()
        return signals

    def _angle_for_topic(self, topic: str) -> str:
        angles = {
            "AI in financial infrastructure": "Position JCM as builder of observability layers, not AI stock pickers",
            "African fintech and capital markets": "Gulu-to-global builder narrative; Uganda depth",
            "Uganda Treasury bills and bonds": "Repurpose podcast episode; conservative portfolio angle",
            "Quantitative trading systems": "Infrastructure beats signals — link to systematic discipline",
        }
        return angles.get(topic, f"Educational LinkedIn post on: {topic}")

    async def _persist_cycle_report(
        self,
        trends: list[MarketingTrendSignal],
        generated: list[MarketingContentQueue],
    ) -> MarketingCycleReport:
        today = date.today()
        result = await self.db.execute(
            select(MarketingCycleReport).where(MarketingCycleReport.cycle_date == today)
        )
        row = result.scalar_one_or_none()
        if row is None:
            row = MarketingCycleReport(cycle_date=today)
            self.db.add(row)

        row.items_generated = len(generated)
        row.trends_scanned = len(trends)
        row.report_json = {
            "generated_titles": [g.title for g in generated],
            "trend_topics": [t.topic for t in trends],
            "brand_line": self.engine.get_brand_summary()["master_line"],
        }
        await self.db.flush()
        return row

    async def get_queue(
        self,
        status: str | None = "draft",
        platform: str | None = None,
        limit: int = 50,
    ) -> list[MarketingContentQueue]:
        query = select(MarketingContentQueue).order_by(
            MarketingContentQueue.scheduled_for.asc().nullslast(),
            MarketingContentQueue.created_at.desc(),
        ).limit(limit)
        if status:
            query = query.where(MarketingContentQueue.status == status)
        if platform:
            query = query.where(MarketingContentQueue.platform == platform)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def approve_content(self, content_id: str, approved_by: str = "human") -> MarketingContentQueue | None:
        from uuid import UUID

        result = await self.db.execute(
            select(MarketingContentQueue).where(MarketingContentQueue.id == UUID(content_id))
        )
        row = result.scalar_one_or_none()
        if not row:
            return None
        warnings = validate_content(row.body)
        if warnings:
            row.content_metadata = {
                **(row.content_metadata or {}),
                "compliance_warnings": warnings,
            }
        row.status = "approved"
        row.updated_at = datetime.now(timezone.utc)
        row.content_metadata = {**(row.content_metadata or {}), "approved_by": approved_by}
        await self.db.flush()
        return row

    async def get_trends(self, limit: int = 20) -> list[MarketingTrendSignal]:
        result = await self.db.execute(
            select(MarketingTrendSignal)
            .where(MarketingTrendSignal.acted_on == False)  # noqa: E712
            .order_by(MarketingTrendSignal.relevance_score.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    async def get_stats(self) -> dict[str, Any]:
        draft = await self.db.execute(
            select(func.count(MarketingContentQueue.id)).where(
                MarketingContentQueue.status == "draft"
            )
        )
        approved = await self.db.execute(
            select(func.count(MarketingContentQueue.id)).where(
                MarketingContentQueue.status == "approved"
            )
        )
        draft_count = draft.scalar() or 0
        MARKETING_CONTENT_QUEUE.set(draft_count)
        return {
            "draft_count": draft_count,
            "approved_count": approved.scalar() or 0,
            "brand": self.engine.get_brand_summary(),
        }

    def load_docs_brand_kit(self) -> str | None:
        """Optional: load BRAND_INTELLIGENCE.md from mounted docs path."""
        settings = get_settings()
        path = Path(settings.marketing_docs_path) / "BRAND_INTELLIGENCE.md"
        if path.exists():
            return path.read_text(encoding="utf-8")
        return None
