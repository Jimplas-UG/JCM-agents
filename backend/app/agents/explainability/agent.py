"""Explainability Agent — audit trail for every BSv3.2 system event."""

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.base import BaseAgent
from app.models.tables import AuditTrail


class ExplainabilityAgent(BaseAgent):
    name = "explainability"
    description = "Structured explanations for trades, blocks, risk changes, kill-switch events"

    async def run_cycle(self) -> dict[str, Any]:
        result = await self.db.execute(
            select(AuditTrail).order_by(AuditTrail.created_at.desc()).limit(1)
        )
        latest = result.scalar_one_or_none()
        return {
            "status": "ok",
            "latest_audit": latest.reference_id if latest else None,
        }

    async def explain_trade_approved(self, payload: dict[str, Any]) -> AuditTrail:
        filters_passed = payload.get("filters_passed", [])
        explanation = {
            "decision": "trade_approved",
            "symbol": payload.get("symbol"),
            "direction": payload.get("direction"),
            "filters_passed": filters_passed,
            "filters_blocked": payload.get("filters_blocked", []),
            "filter_states": payload.get("filter_states", {}),
            "market_regime": payload.get("market_regime"),
            "trading_session": payload.get("trading_session"),
            "bsv32_confidence": payload.get("bsv32_confidence"),
            "dxy_state": payload.get("dxy_state"),
            "yield_state": payload.get("yield_state"),
            "rationale": self._build_approval_rationale(payload),
        }
        human = self._format_human_readable(explanation, "approved")
        return await self._persist(
            event_type="trade_executed",
            reference_id=payload.get("event_id"),
            summary=f"Trade approved: {payload.get('symbol')} {payload.get('direction')}",
            explanation=explanation,
            human_readable=human,
            severity="info",
        )

    async def explain_trade_blocked(self, payload: dict[str, Any]) -> AuditTrail:
        blocked_by = payload.get("blocked_by", [])
        explanation = {
            "decision": "trade_blocked",
            "symbol": payload.get("symbol"),
            "direction": payload.get("direction"),
            "blocked_by": blocked_by,
            "filter_states": payload.get("filter_states", {}),
            "market_regime": payload.get("market_regime"),
            "trading_session": payload.get("trading_session"),
            "dxy_state": payload.get("dxy_state"),
            "yield_state": payload.get("yield_state"),
            "market_context": {
                "geopolitical": payload.get("geopolitical_flag"),
                "nfp_blackout": payload.get("nfp_blackout_active"),
                "chop_zone": payload.get("chop_zone_active"),
                "ath_zone": payload.get("ath_zone_active"),
            },
            "rationale": (
                f"BSv3.2 blocked trade due to: {', '.join(blocked_by)}. "
                f"Market regime: {payload.get('market_regime', 'unknown')}."
            ),
        }
        human = self._format_human_readable(explanation, "blocked")
        return await self._persist(
            event_type="trade_blocked",
            reference_id=payload.get("event_id"),
            summary=f"Trade blocked: {payload.get('symbol')} — {', '.join(blocked_by)}",
            explanation=explanation,
            human_readable=human,
            severity="info",
        )

    async def explain_kill_switch(self, payload: dict[str, Any]) -> AuditTrail:
        explanation = {
            "decision": "kill_switch",
            "trigger": payload.get("trigger"),
            "state_snapshot": payload,
            "rationale": "Kill-switch activated — full state snapshot captured for human review.",
        }
        return await self._persist(
            event_type="kill_switch",
            reference_id=payload.get("event_id"),
            summary="Kill-switch event — state snapshot recorded",
            explanation=explanation,
            human_readable=str(explanation["rationale"]),
            severity="emergency",
        )

    async def explain_confidence_shift(self, payload: dict[str, Any]) -> AuditTrail:
        explanation = {
            "decision": "confidence_shift",
            "previous": payload.get("previous_confidence"),
            "current": payload.get("current_confidence"),
            "drivers": payload.get("drivers", []),
            "rationale": (
                f"Confidence shifted from {payload.get('previous_confidence')} "
                f"to {payload.get('current_confidence')}. "
                f"Drivers: {', '.join(payload.get('drivers', []))}"
            ),
        }
        return await self._persist(
            event_type="confidence_shift",
            reference_id=payload.get("event_id"),
            summary="BSv3.2 confidence score shift detected",
            explanation=explanation,
            human_readable=explanation["rationale"],
            severity="warning",
        )

    async def explain_risk_change(self, payload: dict[str, Any]) -> AuditTrail:
        explanation = {
            "decision": "risk_parameter_change",
            "changes": payload.get("changes", {}),
            "trigger": payload.get("trigger"),
            "rationale": f"Risk parameters changed: {payload.get('changes', {})}",
        }
        return await self._persist(
            event_type="risk_parameter_change",
            reference_id=payload.get("event_id"),
            summary="Risk parameter change recorded",
            explanation=explanation,
            human_readable=explanation["rationale"],
            severity="warning",
        )

    async def on_event(self, event_type: str, payload: dict[str, Any]) -> None:
        handlers = {
            "trade_executed": self.explain_trade_approved,
            "trade_blocked": self.explain_trade_blocked,
            "kill_switch": self.explain_kill_switch,
            "confidence_shift": self.explain_confidence_shift,
            "risk_parameter_change": self.explain_risk_change,
        }
        handler = handlers.get(event_type)
        if handler:
            await handler(payload)

    def _build_approval_rationale(self, payload: dict[str, Any]) -> str:
        passed = payload.get("filters_passed", [])
        regime = payload.get("market_regime", "unknown")
        session = payload.get("trading_session", "unknown")
        conf = payload.get("bsv32_confidence")
        parts = [
            f"All required BSv3.2 filters passed: {', '.join(passed) or 'default path'}.",
            f"Market regime: {regime}. Session: {session}.",
        ]
        if conf is not None:
            parts.append(f"Confidence score: {conf}.")
        return " ".join(parts)

    def _format_human_readable(self, explanation: dict, decision: str) -> str:
        symbol = explanation.get("symbol", "N/A")
        direction = explanation.get("direction", "")
        if decision == "approved":
            return (
                f"[APPROVED] {symbol} {direction}\n"
                f"Filters passed: {', '.join(explanation.get('filters_passed', []))}\n"
                f"Regime: {explanation.get('market_regime')} | "
                f"Session: {explanation.get('trading_session')}\n"
                f"{explanation.get('rationale', '')}"
            )
        return (
            f"[BLOCKED] {symbol} {direction}\n"
            f"Blocked by: {', '.join(explanation.get('blocked_by', []))}\n"
            f"{explanation.get('rationale', '')}"
        )

    async def _persist(
        self,
        event_type: str,
        reference_id: str | None,
        summary: str,
        explanation: dict,
        human_readable: str,
        severity: str,
    ) -> AuditTrail:
        entry = AuditTrail(
            event_type=event_type,
            reference_id=reference_id,
            summary=summary,
            explanation_json=explanation,
            human_readable=human_readable,
            severity=severity,
        )
        self.db.add(entry)
        await self.db.flush()
        self.logger.info("audit_recorded", event_type=event_type, ref=reference_id)
        return entry

    async def get_recent_audits(self, limit: int = 50) -> list[AuditTrail]:
        result = await self.db.execute(
            select(AuditTrail).order_by(AuditTrail.created_at.desc()).limit(limit)
        )
        return list(result.scalars().all())
