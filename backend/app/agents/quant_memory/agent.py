"""Quant Memory Agent — institutional memory for BSv3.2 trade events."""

import json
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.db.redis_client import CHANNEL_SYSTEM_STATE, CHANNEL_TRADE_EVENTS, publish
from app.models.tables import (
    Bsv32FilterName,
    EventType,
    FilterBlockEvent,
    MarketRegime,
    SystemStateSnapshot,
    TradeDirection,
    TradeEvent,
    TradeOutcome,
    TradingSession,
)
from app.schemas.events import FilterBlockIngest, SystemStateIngest, TradeEventIngest
from app.utils.enums import coerce_enum, coerce_enum_list


class QuantMemoryAgent(BaseAgent):
    name = "quant_memory"
    description = "Records BSv3.2 trade events, filter states, and system snapshots"

    async def record_trade_event(self, data: TradeEventIngest) -> tuple[TradeEvent, bool]:
        if data.event_type == "trade_closed":
            return await self._close_trade_event(data)

        existing = await self.db.execute(
            select(TradeEvent).where(TradeEvent.event_id == data.event_id)
        )
        found = existing.scalar_one_or_none()
        if found:
            self.logger.info("trade_event_duplicate", event_id=data.event_id)
            return found, False

        return await self._insert_trade_event(data)

    async def _insert_trade_event(self, data: TradeEventIngest) -> tuple[TradeEvent, bool]:
        vps = data.vps_health
        event = TradeEvent(
            event_id=data.event_id,
            event_type=coerce_enum(EventType, data.event_type, EventType.trade_executed),
            created_at=data.timestamp or datetime.now(timezone.utc),
            symbol=data.symbol,
            direction=coerce_enum(TradeDirection, data.direction),
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
            outcome=coerce_enum(TradeOutcome, data.outcome, TradeOutcome.open),
            pnl_usd=Decimal(str(data.pnl_usd)) if data.pnl_usd else None,
            filter_states=data.filter_states,
            filters_passed=data.filters_passed,
            filters_blocked=data.filters_blocked,
            market_regime=coerce_enum(MarketRegime, data.market_regime, MarketRegime.unknown),
            trading_session=coerce_enum(
                TradingSession, data.trading_session, TradingSession.off_session
            ),
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
        return event, True

    async def _close_trade_event(self, data: TradeEventIngest) -> tuple[TradeEvent, bool]:
        existing = await self.db.execute(
            select(TradeEvent).where(TradeEvent.event_id == data.event_id)
        )
        found = existing.scalar_one_or_none()
        if found:
            self.logger.info("trade_close_duplicate", event_id=data.event_id)
            return found, False

        raw = data.raw_payload or {}
        open_event_id = raw.get("open_event_id")
        mt5_ticket = raw.get("mt5_ticket")
        open_trade: TradeEvent | None = None

        if open_event_id:
            result = await self.db.execute(
                select(TradeEvent).where(TradeEvent.event_id == open_event_id)
            )
            open_trade = result.scalar_one_or_none()

        if not open_trade and mt5_ticket is not None:
            open_rows = await self.db.execute(
                select(TradeEvent).where(TradeEvent.outcome == TradeOutcome.open)
            )
            for candidate in open_rows.scalars().all():
                rp = candidate.raw_payload or {}
                if rp.get("mt5_ticket") == mt5_ticket:
                    open_trade = candidate
                    break

        if not open_trade and data.symbol and data.direction:
            direction = coerce_enum(TradeDirection, data.direction)
            result = await self.db.execute(
                select(TradeEvent)
                .where(
                    TradeEvent.symbol == data.symbol,
                    TradeEvent.direction == direction,
                    TradeEvent.outcome == TradeOutcome.open,
                )
                .order_by(TradeEvent.created_at.desc())
                .limit(1)
            )
            open_trade = result.scalar_one_or_none()

        if not open_trade:
            self.logger.warning(
                "trade_close_no_open_match",
                event_id=data.event_id,
                symbol=data.symbol,
            )
            return await self._insert_trade_event(data)

        merged_raw = {**(open_trade.raw_payload or {}), **raw}
        merged_raw["close_event_id"] = data.event_id
        open_trade.exit_price = (
            Decimal(str(data.exit_price)) if data.exit_price is not None else open_trade.exit_price
        )
        if data.pnl_usd is not None:
            open_trade.pnl_usd = Decimal(str(data.pnl_usd))
        if data.pips is not None:
            open_trade.pips = Decimal(str(data.pips))
        open_trade.outcome = coerce_enum(TradeOutcome, data.outcome, TradeOutcome.open)
        open_trade.event_type = EventType.trade_closed
        open_trade.raw_payload = merged_raw
        await self.db.flush()

        await publish(
            CHANNEL_TRADE_EVENTS,
            json.dumps(
                {
                    "event_id": data.event_id,
                    "type": "trade_closed",
                    "symbol": data.symbol,
                    "open_event_id": open_trade.event_id,
                }
            ),
        )
        self.logger.info(
            "trade_event_closed",
            event_id=data.event_id,
            open_event_id=open_trade.event_id,
            symbol=data.symbol,
            outcome=data.outcome,
        )
        return open_trade, True

    async def record_filter_block(self, data: FilterBlockIngest) -> tuple[FilterBlockEvent, bool]:
        existing = await self.db.execute(
            select(FilterBlockEvent).where(FilterBlockEvent.event_id == data.event_id)
        )
        found = existing.scalar_one_or_none()
        if found:
            return found, False

        block = FilterBlockEvent(
            event_id=data.event_id,
            created_at=data.timestamp or datetime.now(timezone.utc),
            symbol=data.symbol,
            direction=coerce_enum(TradeDirection, data.direction),
            blocked_by=coerce_enum_list(Bsv32FilterName, data.blocked_by),
            filter_states=data.filter_states,
            market_regime=coerce_enum(MarketRegime, data.market_regime, MarketRegime.unknown),
            trading_session=coerce_enum(
                TradingSession, data.trading_session, TradingSession.off_session
            ),
            dxy_state=data.dxy_state,
            yield_state=data.yield_state,
            raw_payload=data.raw_payload,
        )
        self.db.add(block)
        await self.db.flush()
        self.logger.info("filter_block_recorded", event_id=data.event_id, blocked_by=data.blocked_by)
        return block, True

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
        await publish(
            CHANNEL_SYSTEM_STATE,
            json.dumps(
                {
                    "bsv32_status": data.bsv32_status,
                    "open_positions": data.open_positions,
                    "floating_pnl": float(data.floating_pnl or 0),
                    "mt5_connected": data.mt5_connected,
                    "at": datetime.now(timezone.utc).isoformat(),
                },
                default=str,
            ),
        )
        try:
            from app.workers.agent_scheduler import mark_ingest_activity

            mark_ingest_activity("quant_memory")
        except Exception:
            pass
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
