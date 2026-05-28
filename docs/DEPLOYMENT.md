# JCM Platform — Deployment Guide

## Prerequisites

| Requirement | Version |
|-------------|---------|
| Docker | 24+ with Compose v2 |
| RAM | 4 GB minimum (8 GB recommended) |
| Disk | 10 GB free |
| OS | Windows Server / Linux VPS |

## Quick deploy (this Windows VPS)

This server runs **Windows Docker** (not Linux containers). Use the **native** deploy path:

```powershell
cd "C:\Users\Administrator\Documents\JCM agents\JCM-agents"

.\scripts\pre-deploy.ps1
.\scripts\deploy-native.ps1 -Start

# Verify
Invoke-RestMethod http://104.194.140.203:8000/health
```

Uses local **PostgreSQL 17** and **Redis** already on the host.

### Linux Docker deploy (other servers)

Only on hosts with `OSType: linux` in `docker info`:

```powershell
.\scripts\deploy.ps1 -Build
```

## First-time setup

```powershell
Copy-Item .env.example .env
# Edit .env — set API_SECRET_KEY, POSTGRES_PASSWORD, EVENT_WEBHOOK_SECRET
.\scripts\pre-deploy.ps1
.\scripts\deploy.ps1 -Build
```

Generate random secrets (PowerShell):

```powershell
[Convert]::ToBase64String((1..32 | ForEach-Object { Get-Random -Maximum 256 }))
```

## Services

| Service | Port | URL |
|---------|------|-----|
| API | 8000 | `http://<host>:8000` |
| CEO Dashboard | 3000 | `http://<host>:3000` |
| PostgreSQL | 5432 | localhost only |
| Redis | 6379 | localhost only |
| Prometheus | 9090 | localhost only |

## BSv3.2 installation folder

Point JCM at your Bilshenz Strategy v3.2 directory (where `deploy\windows\start-all-now.ps1` lives):

```powershell
.\scripts\set-bsv32-home.ps1 -Path "D:\Trading\BSv3.2"
# or edit .env directly:
# BSV32_HOME=D:\Trading\BSv3.2

.\scripts\wire-bsv32-integration.ps1
```

Default if unset: `C:\opt\bilshenz`. Override for one run: `.\scripts\wire-bsv32-integration.ps1 -Bsv32Home "D:\path"`.

## Environment variables (critical)

| Variable | Purpose |
|----------|---------|
| `BSV32_HOME` | Path to BSv3.2 / Bilshenz install folder |
| `PLATFORM_PUBLIC_URL` | Public API base (e.g. `http://104.194.140.203:8000`) |
| `API_SECRET_KEY` | Admin API auth + dashboard POST actions |
| `EVENT_WEBHOOK_SECRET` | BSv3.2 webhook header `X-Webhook-Secret` |
| `POSTGRES_PASSWORD` | Database password |
| `NEXT_PUBLIC_API_KEY` | Must match `API_SECRET_KEY` (set by deploy script) |

`deploy.ps1` automatically sets Docker-internal hosts (`postgres`, `redis`) and `host.docker.internal` for Bilshenz APIs on the host.

## BSv3.2 webhook

Point your execution layer to:

```
POST http://104.194.140.203:8000/ingest/event
Header: X-Webhook-Secret: <EVENT_WEBHOOK_SECRET from .env>
```

## Operations

```powershell
# Logs
docker compose logs -f api
docker compose logs -f agents-worker

# Restart
docker compose restart api agents-worker

# Stop
docker compose down

# Full rebuild
docker compose down
.\scripts\deploy.ps1 -Build
```

## Existing database migration

If Postgres volume exists from before Marketing Agent:

```powershell
Get-Content backend\db\migrations\002_marketing.sql | docker exec -i jcm-postgres psql -U jcm_admin -d jcm_bsv32
```

## Firewall (VPS)

Allow inbound:

- **8000** — API + webhooks
- **3000** — CEO dashboard

Do **not** expose 5432, 6379, or 9090 publicly (compose binds them to 127.0.0.1).

## Troubleshooting

| Issue | Fix |
|-------|-----|
| API `degraded` | Check `docker compose logs api` — DB/Redis connection |
| Dashboard can't POST | Set `NEXT_PUBLIC_API_KEY` = `API_SECRET_KEY`, rebuild frontend |
| Out of memory | Set `UVICORN_WORKERS=1` in `.env` (default) |
| Bilshenz APIs unreachable | Confirm sidecars on host; URLs use `host.docker.internal` |

See also [SECURITY.md](SECURITY.md).
