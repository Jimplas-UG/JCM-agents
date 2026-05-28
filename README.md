# Jimplas Capital Management — BSv3.2 Supervisory Platform

Institutional-grade intelligence, analytics, and infrastructure layers for **Bilshenz Strategy v3.2 (BSv3.2)**.

> **Critical:** This platform **observes** the BSv3.2 execution engine. It does **not** modify, replicate, or override any deterministic strategy logic, filters, or risk rules.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full service diagram and data flow.

```
JCM Agents/
├── backend/                 # FastAPI + 9 supervisory agents
│   ├── app/
│   │   ├── agents/          # Quant Memory, Performance Intel, Infra, Risk, etc.
│   │   ├── api/routes/      # REST + WebSocket
│   │   ├── db/              # PostgreSQL session + Redis
│   │   ├── models/          # SQLAlchemy ORM
│   │   ├── services/        # Event pipeline, alerting
│   │   └── workers/         # Background agent scheduler
│   └── db/init.sql          # PostgreSQL schema
├── frontend/                # Next.js CEO mission control dashboard
├── infra/                   # Prometheus, emergency runbooks
├── docker-compose.yml
└── .env.example
```

## The 9 Platform Agents

| # | Agent | Role |
|---|-------|------|
| 1 | **Quant Memory** | Records trade events, filter states, regime/session tags |
| 2 | **Performance Intelligence** | Win rate segmentation, expectancy, edge decay, filter efficiency |
| 3 | **Infrastructure Resilience** | VPS/API health, self-healing, priority alerts |
| 4 | **Portfolio Risk Orchestrator** | Exposure, correlation, drawdown, informational lot scaling |
| 5 | **Execution Quality** | Slippage, spread, fill speed, broker degradation alerts |
| 6 | **Explainability** | Structured audit trail for every BSv3.2 decision |
| 7 | **Research Evolution** | Drift detection → human review queue (no auto-deploy) |
| 8 | **CEO Copilot** | Daily briefing, mission-control dashboard data |
| 9 | **Marketing Agent** | JCM brand content, trends, social review queue (human approve) |

## Quick Start

### Prerequisites

- Docker & Docker Compose
- BSv3.2 execution layer configured to POST events to this platform

### Deploy (production)

**Windows Server (this VPS)** — native, no Linux Docker:

```powershell
.\scripts\pre-deploy.ps1
.\scripts\deploy-native.ps1 -Start
.\scripts\stop-platform.ps1    # to stop
```

**Linux Docker hosts:**

```powershell
.\scripts\pre-deploy.ps1
.\scripts\deploy.ps1 -Build
```

See **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** for full operations guide.

### Manual launch

```bash
docker compose up -d --build
```

| Service | URL |
|---------|-----|
| API | http://localhost:8000 |
| API Docs | http://localhost:8000/docs |
| CEO Dashboard | http://localhost:3000 |
| Prometheus | http://localhost:9090 |
| Metrics | http://localhost:8000/metrics |

### 3. Wire BSv3.2 Event Webhook

Configure your BSv3.2 execution layer to POST events:

```
POST http://<platform-host>:8000/ingest/event
Header: X-Webhook-Secret: <EVENT_WEBHOOK_SECRET>
```

Example payload:

```json
{
  "event_type": "trade_executed",
  "payload": {
    "event_id": "bsv32-20240527-001",
    "symbol": "XAUUSD",
    "direction": "long",
    "lot_size": 0.1,
    "entry_price": 2345.50,
    "filled_price": 2345.62,
    "filter_states": { "nfp_blackout": "passed", "yield_filter": "passed" },
    "filters_passed": ["nfp_blackout", "yield_filter", "dxy_filter"],
    "market_regime": "trending_bull",
    "trading_session": "london",
    "bsv32_confidence": 0.82
  }
}
```

Test with the sample script:

```bash
pip install httpx
python scripts/sample_event_ingest.py
```

### 4. Local Development (without Docker)

**Backend:**

```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
# Start PostgreSQL + Redis locally, apply db/init.sql
uvicorn app.main:app --reload --port 8000
```

**Agent worker:**

```bash
python -m app.workers.agent_scheduler
```

**Frontend:**

```bash
cd frontend
npm install
npm run dev
```

## API Endpoints

| Endpoint | Description |
|----------|-------------|
| `POST /ingest/event` | Ingest BSv3.2 event (webhook) |
| `GET /dashboard/overview` | CEO overview metrics |
| `GET /dashboard/risk` | Risk exposure snapshot |
| `GET /dashboard/infrastructure` | VPS/API health |
| `GET /dashboard/execution-quality` | Broker execution metrics |
| `GET /dashboard/performance` | Daily performance report |
| `GET /dashboard/audit` | Explainability audit trail |
| `GET /dashboard/alerts` | Active system alerts |
| `GET /dashboard/research` | Human review queue |
| `GET /dashboard/briefing` | CEO daily briefing |
| `GET /marketing/brand` | JCM brand kit |
| `GET /marketing/queue` | Marketing content review queue |
| `POST /marketing/cycle` | Run marketing agent cycle |
| `WS /ws` | Real-time dashboard updates |
| `GET /metrics` | Prometheus metrics |
| `GET /health` | Health check |

## Prometheus Metrics

- `jcm_trade_events_total` — Events ingested by type/symbol
- `jcm_filter_blocks_total` — Filter block count
- `jcm_risk_score` — Current portfolio risk score
- `jcm_infra_health_score` — Infrastructure health
- `jcm_execution_slippage_pips` — Slippage histogram
- `jcm_agent_cycle_duration_seconds` — Agent performance

## Emergency Procedures

See [infra/runbooks/EMERGENCY.md](infra/runbooks/EMERGENCY.md).

## Integration with Existing Systems

| System | Integration | Mode |
|--------|-------------|------|
| MT5 API | Health checks, reconnect via Watchdog | Read-only |
| Desk API | Position/account state polling | Read-only |
| Forward Bot API | Signal delivery monitoring | Read-only |
| Watchdog API | VPS metrics, service remediation | Read-only |
| BSv3.2 Engine | Event webhooks | Read-only observer |

## Security

See [docs/SECURITY.md](docs/SECURITY.md) for production hardening, auth headers, and rate limits.

```bash
python scripts/security_check.py
cd backend && pytest tests/ -v
```

## Non-Negotiables

- Never modify BSv3.2 core logic
- Never use LLM for trading decisions
- Never replace deterministic filter behaviour
- Never auto-deploy strategy changes
- All AI involvement is supervisory and analytical only

---

**Jimplas Capital Management** — Institutional fintech infrastructure for BSv3.2.
