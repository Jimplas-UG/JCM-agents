"""Quant Memory Agent — institutional memory for BSv3.2 trade events."""

import json
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.db.redis_client import CHANNEL_TRADE_EVENTS, publish
from app.models.tables import FilterBlockEvent, SystemStateSnapshot, TradeEvent
from app.schemas.events import FilterBlockIngest, SystemStateIngest, TradeEventIngest


class QuantMemoryAgent(BaseAgent):
    name = "quant_memory"
    description = "Records BSv3.2 trade events, filter states, and system snapshots"

    async def record_trade_event(self, data: TradeEventIngest) -> TradeEvent:
        vps = data.vps_health
        event = TradeEvent(
            event_id=data.event_id,
            event_type=data.event_type,
            created_at=data.timestamp or datetime.now(timezone.utc),
            symbol=data.symbol,
            direction=data.direction,
            lot_size=Decimal(str(data.lot_size)) if data.lot_size else None,
            entry_price=Decimal(str(data.entry_price)) if data.entry_price else None,
            exit_price=Decimal(str(data.exit_price)) if data.exit_price else None,
            stop_loss=Decimal(str(data.stop_loss)) if data.stop_loss else None,
            take_profit=Decimal(str(data.take_profit)) if data.take_profit else None,
            requested_price=Decimal(str(data.requested_price)) if data.requested_price else None,
            filled_price=Decimal(str(data.filled_price)) if data.filled_price else None,
            slippage_pips=Decimal(str(data.slippage_pips)) if data.slippage_pips else None,
            spread_at_entry=Decimal(str(data.spread_at_entry)) if data.spread_at_entry else None,
            spread_avg_24h=Decimal(str(data.spread_avg_24h)) if data.spread_avg_24h else None,
            execution_latency_ms=data.execution_latency_ms,
            pips=Decimal(str(data.pips)) if data.pips else None,
            r_multiple=Decimal(str(data.r_multiple)) if data.r_multiple else None,
            outcome=data.outcome,
            pnl_usd=Decimal(str(data.pnl_usd)) if data.pnl_usd else None,
            filter_states=data.filter_states,
            filters_passed=data.filters_passed,
            filters_blocked=data.filters_blocked,
            market_regime=data.market_regime,
            trading_session=data.trading_session,
            dxy_value=Decimal(str(data.dxy_value)) if data.dxy_value else None,
            dxy_state=data.dxy_state,
            yield_10y=Decimal(str(data.yield_10y)) if data.yield_10y else None,
            yield_state=data.yield_state,
            volatility_state=data.volatility_state,
            geopolitical_flag=data.geopolitical_flag,
            ath_zone_active=data.ath_zone_active,
            chop_zone_active=data.chop_zone_active,
            nfp_blackout_active=data.nfp_blackout_active,
            bsv32_confidence=Decimal(str(data.bsv32_confidence)) if data.bsv32_confidence else None,
            bsv32_version=data.bsv32_version,
            vps_cpu_pct=Decimal(str(vps.cpu_pct)) if vps and vps.cpu_pct else None,
            vps_ram_pct=Decimal(str(vps.ram_pct)) if vps and vps.ram_pct else None,
            vps_disk_pct=Decimal(str(vps.disk_pct)) if vps and vps.disk_pct else None,
            mt5_connected=vps.mt5_connected if vps else None,
            raw_payload=data.raw_payload,
        )
        self.db.add(event)
        await self.db.flush()

        await publish(
            CHANNEL_TRADE_EVENTS,
            json.dumps({"event_id": data.event_id, "type": data.event_type, "symbol": data.symbol}),
        )
        self.logger.info("trade_event_recorded", event_id=data.event_id, symbol=data.symbol)
        return event

    async def record_filter_block(self, data: FilterBlockIngest) -> FilterBlockEvent:
        block = FilterBlockEvent(
            event_id=data.event_id,
            created_at=data.timestamp or datetime.now(timezone.utc),
            symbol=data.symbol,
            direction=data.direction,
            blocked_by=data.blocked_by,
            filter_states=data.filter_states,
            market_regime=data.market_regime,
            trading_session=data.trading_session,
            dxy_state=data.dxy_state,
            yield_state=data.yield_state,
            raw_payload=data.raw_payload,
        )
        self.db.add(block)
        await self.db.flush()
        self.logger.info("filter_block_recorded", event_id=data.event_id, blocked_by=data.blocked_by)
        return block

    async def record_system_state(self, data: SystemStateIngest) -> SystemStateSnapshot:
        snapshot = SystemStateSnapshot(
            bsv32_status=data.bsv32_status,
            nfp_blackout=data.nfp_blackout,
            yield_filter_state=data.yield_filter_state,
            dxy_filter_state=data.dxy_filter_state,
            ath_zone_active=data.ath_zone_active,
            geopolitical_active=data.geopolitical_active,
            chop_zone_active=data.chop_zone_active,
            risk_gating_active=data.risk_gating_active,
            watchdog_ok=data.watchdog_ok,
            mt5_connected=data.mt5_connected,
            desk_api_ok=data.desk_api_ok,
            forward_bot_ok=data.forward_bot_ok,
            watchdog_api_ok=data.watchdog_api_ok,
            open_positions=data.open_positions,
            account_equity=Decimal(str(data.account_equity)) if data.account_equity else None,
            account_balance=Decimal(str(data.account_balance)) if data.account_balance else None,
            floating_pnl=Decimal(str(data.floating_pnl)) if data.floating_pnl else None,
            daily_pnl=Decimal(str(data.daily_pnl)) if data.daily_pnl else None,
            drawdown_pct=Decimal(str(data.drawdown_pct)) if data.drawdown_pct else None,
            market_regime=data.market_regime,
            raw_snapshot=data.raw_snapshot,
        )
        self.db.add(snapshot)
        await self.db.flush()
        return snapshot

    async def on_event(self, event_type: str, payload: dict[str, Any]) -> None:
        if event_type == "trade_executed" or event_type == "trade_closed":
            await self.record_trade_event(TradeEventIngest(**payload))
        elif event_type == "trade_blocked":
            await self.record_filter_block(FilterBlockIngest(**payload))
        elif event_type == "system_state":
            await self.record_system_state(SystemStateIngest(**payload))

    async def run_cycle(self) -> dict[str, Any]:
        result = await self.db.execute(
            select(TradeEvent).order_by(TradeEvent.created_at.desc()).limit(1)
        )
        latest = result.scalar_one_or_none()
        return {
            "status": "ok",
            "latest_event_id": latest.event_id if latest else None,
            "latest_timestamp": latest.created_at.isoformat() if latest else None,
        }

    async def get_recent_trades(self, limit: int = 50) -> list[TradeEvent]:
        result = await self.db.execute(
            select(TradeEvent).order_by(TradeEvent.created_at.desc()).limit(limit)
        )
        return list(result.scalars().all())
