"""Infrastructure subscription renewal reminders (Cursor, Cloudzy, etc.)."""

from __future__ import annotations

import json
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any

from app.config import get_settings

_SUBSCRIPTIONS_FILE = (
    Path(__file__).resolve().parent.parent.parent / "infra" / "subscriptions.json"
)


def _add_month(d: date) -> date:
    month = d.month + 1
    year = d.year
    if month > 12:
        month = 1
        year += 1
    day = min(d.day, 28 if month == 2 else 30 if month in (4, 6, 9, 11) else 31)
    return date(year, month, day)


def _status_for_days(days_left: int) -> str:
    if days_left < 0:
        return "expired"
    if days_left <= 7:
        return "urgent"
    if days_left <= 30:
        return "soon"
    return "ok"


def _enrich_item(raw: dict[str, Any], today: date) -> dict[str, Any]:
    billing_status = raw.get("billing_status")
    if not billing_status and str(raw.get("status", "")).lower() in (
        "active",
        "trialing",
        "cancelled",
        "past_due",
    ):
        billing_status = raw.get("status")

    expires_raw = raw.get("expires_on") or raw.get("expires")
    if not expires_raw:
        return {
            **raw,
            "billing_status": billing_status,
            "days_left": None,
            "status": "unknown",
        }
    expires = date.fromisoformat(str(expires_raw)[:10])
    days_left = (expires - today).days
    return {
        **{k: v for k, v in raw.items() if k != "status" or str(v).lower() not in ("active", "trialing")},
        "billing_status": billing_status,
        "expires_on": expires.isoformat(),
        "days_left": days_left,
        "status": _status_for_days(days_left),
        "display_date": expires.strftime("%d %b %Y"),
    }


def get_subscription_reminders() -> dict[str, Any]:
    """Load subscriptions from JSON + env overrides; compute days until expiry."""
    settings = get_settings()
    today = date.today()
    items: list[dict[str, Any]] = []

    if _SUBSCRIPTIONS_FILE.exists():
        try:
            payload = json.loads(_SUBSCRIPTIONS_FILE.read_text(encoding="utf-8"))
            items = list(payload.get("subscriptions") or [])
        except (json.JSONDecodeError, OSError):
            items = []

    env_overrides = {
        "cursor": settings.cursor_subscription_expires,
        "cloudzy": settings.cloudzy_subscription_expires,
    }
    for item in items:
        sid = str(item.get("id", "")).lower()
        override = env_overrides.get(sid, "").strip()
        if override:
            item["expires_on"] = override[:10]
            item["source"] = "env"

    for sid, override in env_overrides.items():
        if not override.strip():
            continue
        if any(str(i.get("id", "")).lower() == sid for i in items):
            continue
        items.append(
            {
                "id": sid,
                "label": "Cursor Pro" if sid == "cursor" else "Cloudzy VPS",
                "expires_on": override[:10],
                "source": "env",
            }
        )

    enriched = [_enrich_item(i, today) for i in items]
    enriched.sort(key=lambda x: (x.get("days_left") is None, x.get("days_left") or 9999))

    return {
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "today": today.isoformat(),
        "subscriptions": enriched,
        "has_urgent": any(s.get("status") in ("urgent", "expired") for s in enriched),
    }
