"""Event ingestion pipeline — routes BSv3.2 events to supervisory agents."""

from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.agents import (
    CeoCopilotAgent,
    ExecutionQualityAgent,
    ExplainabilityAgent,
    QuantMemoryAgent,
)
from app.logging_config import get_logger
from app.schemas.events import FilterBlockIngest, SystemStateIngest, TradeEventIngest

logger = get_logger("event_pipeline")


class EventPipeline:
    """
    Central event router.

    Observes BSv3.2 events — never modifies strategy logic.
    """

    def __init__(self, db: AsyncSession):
        self.db = db
        self.memory = QuantMemoryAgent(db)
        self.explain = ExplainabilityAgent(db)
        self.execution = ExecutionQualityAgent(db)

    async def ingest(self, event_type: str, payload: dict[str, Any]) -> dict[str, Any]:
        logger.info("event_ingested", event_type=event_type)

        if event_type == "trade_executed":
            data = TradeEventIngest(**payload)
            trade, created = await self.memory.record_trade_event(data)
            if created:
                await self.explain.explain_trade_approved(payload)
                await self.execution.record_from_trade(trade)
            return {
                "status": "recorded" if created else "duplicate",
                "event_id": data.event_id,
            }

        if event_type == "trade_closed":
            data = TradeEventIngest(**payload)
            trade, created = await self.memory.record_trade_event(data)
            if created:
                await self.explain.explain_trade_closed(payload, trade.event_id)
                await self.execution.record_from_trade(trade)
            return {
                "status": "closed" if created else "duplicate",
                "event_id": data.event_id,
                "open_event_id": trade.event_id,
            }

        if event_type == "trade_blocked":
            data = FilterBlockIngest(**payload)
            _block, created = await self.memory.record_filter_block(data)
            if created:
                await self.explain.explain_trade_blocked(payload)
            return {
                "status": "blocked_recorded" if created else "duplicate",
                "event_id": data.event_id,
            }

        if event_type == "system_state":
            data = SystemStateIngest(**payload)
            await self.memory.record_system_state(data)
            return {"status": "state_recorded"}

        if event_type == "kill_switch":
            await self.explain.explain_kill_switch(payload)
            return {"status": "kill_switch_audited"}

        if event_type == "confidence_shift":
            await self.explain.explain_confidence_shift(payload)
            return {"status": "confidence_audited"}

        if event_type == "risk_parameter_change":
            await self.explain.explain_risk_change(payload)
            return {"status": "risk_change_audited"}

        await self.memory.on_event(event_type, payload)
        return {"status": "forwarded", "event_type": event_type}
