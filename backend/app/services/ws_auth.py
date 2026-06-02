"""Short-lived WebSocket tokens for Mission Control (HMAC, no extra deps)."""

from __future__ import annotations

import base64
import hashlib
import hmac
import time

from app.config import get_settings

_DEFAULT_TTL = 3600


def create_ws_token(username: str, *, ttl_seconds: int | None = None) -> str:
    settings = get_settings()
    secret = settings.api_secret_key or "change-me"
    ttl = ttl_seconds or getattr(settings, "ws_token_ttl_seconds", _DEFAULT_TTL)
    exp = int(time.time()) + ttl
    payload = f"{username}:{exp}"
    sig = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
    raw = f"{payload}:{sig}".encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def verify_ws_token(token: str) -> str | None:
    """Returns username if valid, else None."""
    settings = get_settings()
    secret = settings.api_secret_key or "change-me"
    try:
        pad = "=" * (-len(token) % 4)
        raw = base64.urlsafe_b64decode(token + pad).decode()
        payload, sig = raw.rsplit(":", 1)
        user, exp_s = payload.split(":", 1)
        expected = hmac.new(secret.encode(), payload.encode(), hashlib.sha256).hexdigest()
        if not hmac.compare_digest(sig, expected):
            return None
        if int(exp_s) < time.time():
            return None
        return user
    except Exception:
        return None
