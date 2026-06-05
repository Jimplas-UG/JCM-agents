"""Closed-loop execution halt — JCM risk can stop Bilshenz forward bot via shared safety state."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_SAFETY_PATH = Path(r"C:\logs\tradingbot\safety-state.json")
HALT_AUDIT_PATH = Path(r"C:\logs\tradingbot\allocator-halt.json")


def _safety_path() -> Path:
    import os

    return Path(os.environ.get("SAFETY_STATE_PATH", str(DEFAULT_SAFETY_PATH)))


def _fresh_state() -> dict[str, Any]:
    return {
        "nyDay": None,
        "dayStartEquity": 0,
        "peakEquity": 0,
        "consecutiveApiFailures": 0,
        "failsafe": False,
        "failsafeReason": None,
        "lastExecutedBarT": None,
        "lastOrderIdempotencyKey": None,
    }


def engage_halt(*, reason: str, source: str = "jcm_risk") -> dict[str, Any]:
    """Set Bilshenz safety failsafe — forward bot stops placing live orders."""
    path = _safety_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    state = _fresh_state()
    if path.is_file():
        try:
            state.update(json.loads(path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            pass
    state["failsafe"] = True
    state["failsafeReason"] = reason[:500]
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")

    audit = {
        "engaged_at": datetime.now(timezone.utc).isoformat(),
        "source": source,
        "reason": reason,
        "safety_path": str(path),
    }
    HALT_AUDIT_PATH.parent.mkdir(parents=True, exist_ok=True)
    HALT_AUDIT_PATH.write_text(json.dumps(audit, indent=2), encoding="utf-8")
    return audit


def clear_halt(*, cleared_by: str = "operator") -> dict[str, Any]:
    """Clear failsafe after human review."""
    path = _safety_path()
    state = _fresh_state()
    if path.is_file():
        try:
            state.update(json.loads(path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError):
            pass
    state["failsafe"] = False
    state["failsafeReason"] = None
    state["consecutiveApiFailures"] = 0
    path.write_text(json.dumps(state, indent=2), encoding="utf-8")

    if HALT_AUDIT_PATH.is_file():
        HALT_AUDIT_PATH.unlink(missing_ok=True)
    return {"cleared_at": datetime.now(timezone.utc).isoformat(), "cleared_by": cleared_by}


def halt_status() -> dict[str, Any]:
    path = _safety_path()
    active = False
    reason = None
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            active = bool(data.get("failsafe"))
            reason = data.get("failsafeReason")
        except (json.JSONDecodeError, OSError):
            pass
    return {
        "halt_active": active,
        "reason": reason,
        "safety_path": str(path),
        "audit_file": str(HALT_AUDIT_PATH) if HALT_AUDIT_PATH.is_file() else None,
    }
