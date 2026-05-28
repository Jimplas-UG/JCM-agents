# JCM Platform — Security Guide

## Production checklist

| Setting | Requirement |
|---------|-------------|
| `APP_ENV` | `production` |
| `API_SECRET_KEY` | Strong random value (not `change-me`) |
| `EVENT_WEBHOOK_SECRET` | Strong random value |
| `POSTGRES_PASSWORD` | Strong password (not `changeme`) |
| `METRICS_REQUIRE_AUTH` | `true` (default) |
| `STRICT_SECURITY` | `true` to fail startup on misconfiguration |
| `CORS_ORIGINS` | Only trusted dashboard origins |
| `NEXT_PUBLIC_API_KEY` | Match `API_SECRET_KEY` for dashboard POST actions |

## Authentication

| Surface | Auth |
|---------|------|
| `POST /ingest/*` | `X-Webhook-Secret` (required in production) |
| `POST /marketing/*`, dashboard mutating routes | `X-API-Key` (required in production) |
| `POST /agents/{name}/run` | `X-API-Key` |
| `GET /metrics` | `X-API-Key` (production) |
| `GET /dashboard/*`, `GET /health` | Public (rate-limited) |

## Rate limiting

- Default: **120 requests/minute** per client IP (`RATE_LIMIT_PER_MINUTE`)
- Returns HTTP 429 with `Retry-After: 60`

## Security headers

All responses include:

- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Strict-Transport-Security` (production only)

## Automated checks

```bash
# Configuration scan
python scripts/security_check.py

# Unit & security tests
cd backend
pip install -r requirements-dev.txt
pytest tests/ -v
```

## Network hardening (VPS)

- Expose only ports 443/80 (reverse proxy) — not 5432/6379 publicly
- Restrict Prometheus scraper to internal network; use `X-API-Key` on `/metrics`
- Run `docker compose` behind nginx/Caddy with TLS
