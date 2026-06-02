# JCM Institutional Optimization

**Directive:** Upgrade the existing 9-agent platform to institutional-grade autonomous operations **without adding agents**.

**Audit date:** June 2026  
**Constraint:** BSv3.2 strategy (P1/P2/P3), filters, and forward execution logic are **read-only** — supervisory layer only.

---

## 1. Architecture review

### Current topology

```
BSv3.2 / Forward Bot
        │ webhook (X-Webhook-Secret)
        ▼
┌───────────────────────────────────────┐
│  FastAPI (JCMAPI :8000)               │
│  EventPipeline (sequential on ingest) │
│    → quant_memory → explainability    │
│    → execution_quality                │
└───────────────────────────────────────┘
        │                    │
        ▼                    ▼
   PostgreSQL            Redis pub/sub
        ▲                    │
        │                    ▼
┌───────────────────────────────────────┐
│  agent_scheduler (9 interval jobs)    │
│  + daily_executive_briefing 09:00 EAT │
└───────────────────────────────────────┘
        │
        ▼
   Mission Control (HTML + REST + /ws)
```

### Strengths

- Clear **read-only observer** boundary vs BSv3.2 (`BaseAgent`, ingest-only writes to JCM DB).
- **Human-in-the-loop** for research (`auto_deploy_blocked`) and marketing (`marketing_auto_approve=false`).
- **Event-driven memory** on ingest (trades, blocks, audit) — correct pattern for quant firms.
- **Executive briefing** pipeline with Telegram and Mission Control.
- **Infra resilience** with external health probes and watchdog remediation hooks.

### Structural gaps

| Gap | Impact |
|-----|--------|
| No shared **priority message bus** between scheduled agents | Conflicting alerts/remediations possible |
| **PostgreSQL as only coordination layer** | High query load, no agent-level memory isolation |
| **Triple agent registry** (scheduler, health.py, docs) | Drift risk (marketing interval already diverges) |
| **CEO copilot rebuilds full briefing every 5 min** | Wastes CPU/RAM/DB; duplicates 09:00 run |
| **`load_briefing_context()` on live tick** | 15+ queries + 4 HTTP probes every 5s |
| **Dead Redis channel** `jcm:system_state` | WS subscribers never receive data |
| **Overlapping watchdogs** (VPS scripts + infra agent) | Restart storms |
| **Prometheus gauges unused** | Monitoring blind spots |

### Target architecture (same 9 agents)

1. **Ingest plane** — unchanged contract; add correlation IDs on events.
2. **Mission memory** — `mission_snapshots` + `agent_memory` tables (see §3).
3. **Agent bus** — Redis envelopes with priority + TTL (see §2).
4. **Orchestrator layer** — thin module (not a new agent): conflict matrix, action audit, rate limits.
5. **Command layer** — Mission Control: health scores, audit trail, debounced live path.
6. **Ops plane** — JCMAPI + JCMSchedulerWatchdog + forward ensure (single ownership).

---

## 2. Inter-agent communication

### Today

| Mechanism | Usage |
|-----------|--------|
| `EventPipeline` | Synchronous chain on webhook only |
| PostgreSQL | All scheduled agents read/write shared tables |
| Redis `jcm:trade_events` | quant_memory → WebSocket |
| Redis `jcm:dashboard` | ceo_copilot, marketing → WebSocket |
| Redis `jcm:alerts` | AlertService → WebSocket |
| Redis `jcm:bsv32:lot_scaling` | portfolio_risk cache (informational) |

**No** scheduled agent calls another agent directly.

### Proposed: structured message envelope

```json
{
  "id": "uuid",
  "priority": "critical|high|medium|low",
  "source_agent": "infra_resilience",
  "target": "all|ceo_copilot|orchestrator",
  "action": "alert|remediation_requested|briefing_stale|risk_elevated",
  "payload": {},
  "created_at": "ISO8601",
  "ttl_seconds": 300
}
```

Channel: `jcm:agent_bus` (new). **Orchestrator** (Python module) consumes Critical/High first:

- Blocks duplicate remediation within 5 min window.
- Supersedes lower-priority duplicate alerts (same title hash).
- Logs all messages to `agent_action_log` for audit.

### Priority rules

| Priority | Examples | Consumers |
|----------|----------|-----------|
| Critical | Kill-switch recommended, API down, drawdown breach | Telegram + MC alert strip + orchestrator |
| High | Slippage degradation, infra unhealthy | Alerts + research queue |
| Medium | Marketing cycle complete, briefing ready | Redis dashboard + MC |
| Low | Performance daily written | MC background refresh only |

### Conflict prevention matrix

| Agent A | Agent B | Rule |
|---------|---------|------|
| infra_resilience | infra_resilience | Max 1 remediation per service / 10 min |
| infra_resilience | VPS watchdog | Orchestrator owns restart authority |
| portfolio_risk | research_evolution | Risk alerts take precedence over research queue |
| execution_quality | research_evolution | Single owner for slippage degradation (merge logic) |

---

## 3. Memory architecture

### Layers

| Layer | Store | Owner | Retention |
|-------|-------|-------|-----------|
| **Mission memory** | `mission_snapshots` | ceo_copilot + scheduler | 90 days rolling |
| **Agent memory** | `agent_memory` (agent_name, key, json, updated_at) | Each agent | Per-agent TTL |
| **Canonical quant memory** | Existing tables (`trade_events`, etc.) | quant_memory | Permanent |
| **Learning feedback** | `action_outcomes` | orchestrator | 180 days |

### Mission snapshot (lightweight)

Written after each successful agent cycle and on ingest milestones:

- `snapshot_at`, `bsv32_status`, `risk_score`, `infra_health_score`, `open_positions`, `daily_pnl`, `active_alerts_count`
- Avoids reloading full `load_briefing_context()` for live tick.

### Learning feedback loop

When infra remediates or alert fires:

1. Record `action_outcomes(action, agent, success, latency_ms, metadata)`.
2. Weekly job (performance_intel cycle extension): compute remediation success rate → adjust infra backoff (no strategy impact).

### CEO briefing cache

- `generate_daily_briefing()`: if `CeoBriefing` exists for `today` and `force=false`, return cached JSON.
- Interval job (300s): only `build_live_overview()` + Redis publish if snapshot stale > 60s.

---

## 4. Autonomous operations

### Self-healing (consolidate)

| Component | Role |
|-----------|------|
| **JCMSchedulerWatchdog** (NSSM) | Ensures `agent_scheduler` process alive |
| **JCMAPI** (NSSM) | Ensures Mission Control API |
| **infra_resilience** | Probe + request watchdog remediate (not parallel VPS scripts) |
| **vps-ensure-forward-bot.ps1** | Forward stack only |

**Remove/disable:** overlapping `jcm-scheduler-keepalive`, duplicate `JCM-API-Keepalive`, ad-hoc restart scripts after NSSM stable.

### Failure detection

- Scheduler: if no `agent_cycle_complete` log line in 2× max interval → Critical alert.
- Wire Prometheus: `jcm_active_alerts`, `jcm_risk_score`, `jcm_infra_health_score` updated end of each agent cycle.
- Daily task already: `JCM-Daily-Executive-Briefing` 09:00 Kampala.

---

## 5. Performance optimization

### Critical path fixes

| # | Change | File(s) | Est. impact |
|---|--------|---------|-------------|
| 1 | `GET /dashboard/live-tick` → `build_live_tick()` (MT5 + last mission_snapshot) | `live_dashboard.py`, `dashboard.py` | −80% tick load |
| 2 | Briefing cache by date; copilot interval = overview only | `ceo_copilot/agent.py` | −95% CEO DB |
| 3 | Pass context from `build_executive_briefing` to persist (no double load) | `ceo_copilot/agent.py` | −50% briefing CPU |
| 4 | Debounce WS → live-tick (2s) | `mission-control.html` | −40% burst load |
| 5 | Remove boot duplicate overview fetch | `mission-control.html` | −1 req/session |
| 6 | Batch research filter-drift queries | `research_evolution/agent.py` | −70% research SQL |
| 7 | Index `trade_events` JSONB `mt5_ticket` or column | `quant_memory`, migration | O(1) close match |
| 8 | Skip no-op cycles for quant_memory/explainability when no ingest in 10 min | `agent_scheduler.py` | −2 idle cycles/min |

### Database

- Add composite indexes: `(created_at DESC)` on hot tables already partially covered — verify `trade_events(created_at)`, `alerts(acknowledged, created_at)`.
- Connection pool: document `AsyncSessionLocal` pool size for 10× ingest (load test target).

### Dead code / drift

- Remove or implement `jcm:system_state` publisher.
- Unify `AGENT_INTERVALS` → import from scheduler only (`health.py`).
- Wire or delete unused Prometheus gauges in `prometheus.py`.

---

## 6. Risk management & safety

### Existing guardrails (keep)

- BSv3.2 read-only observer mode.
- Kill-switch **recommendation** only.
- Research `auto_deploy_blocked=True`.
- Marketing compliance validation on approve.

### New guardrails (orchestrator module)

```python
# app/services/agent_orchestrator.py (not a 10th agent)
ALLOWED_WRITE_AGENTS = frozenset({...})  # no bsv32 writes
MAX_REMEDIATIONS_PER_HOUR = 6
FORBIDDEN_ACTIONS = ["modify_strategy", "override_filter", ...]
```

- **Output validation:** numeric fields must be finite; regime labels from enum set; reject LLM-sourced content in trading paths (marketing only).
- **Rogue action detection:** any HTTP call from agents to non-allowlist hosts → log Critical + block.
- **Hallucination heuristic:** briefing claims vs DB snapshot diff → flag "unverified" in MC.

---

## 7. Institutional monitoring

### Per-agent health score (0–100)

Computed after each cycle:

```
score = 100
  - 30 if last cycle failed
  - 20 if duration > 2× baseline
  - 10 if no cycle in 3× interval
```

Expose: `GET /agents/health` → Mission Control grid.

### Dashboard additions (Mission Control)

| Panel | Data source |
|-------|-------------|
| Agent health grid | `/agents/health` |
| System uptime | `infra_health_logs` + process checks |
| Activity log | structured logs API (last 200 events) |
| Audit trail | `audit_trail` filtered |
| Alert stream | WebSocket `jcm:alerts` |

### Audit trail

Already in `explainability` → expose read API with pagination for executives.

---

## 8. Scalability (10× workload)

### Load assumptions

- 10× trade ingest → EventPipeline must stay < 500ms p95 per event (parallelize ingest chain with `asyncio.gather` for independent agents).
- 10× MC users → live-tick must not hit DB (snapshot cache).
- Scheduler: consider separating **heavy** agents (performance_intel, research_evolution) to dedicated worker process **same codebase** — still 9 agents, 2 processes max.

### Resilience tests

1. Burst 1000 ingest events — no OOM, no duplicate trades in quant_memory.
2. Kill scheduler — watchdog restarts within 60s; no duplicate schedulers.
3. Redis down — API degrades gracefully; ingest queues to disk (future).

---

## 9. Executive command layer

### Improvements (no new agents)

- **Real-time Critical strip** — top of MC, WS-driven.
- **Executive summary** — cached briefing + diff vs yesterday snapshot.
- **Strategic recommendations** — aggregate: open research reviews + risk recommendations + marketing pending (read-only cards).
- **Infra subscriptions tab** — already shipped; link renewal dates to alerts 7 days before.

---

## 10. Recommended code improvements (priority order)

### P0 — Week 1 (stability + visibility)

1. `build_live_tick()` lightweight endpoint.
2. Briefing cache by date in `ceo_copilot`.
3. Wire Prometheus gauges in agent cycles.
4. `GET /agents/health` + MC panel.
5. Consolidate VPS watchdogs under NSSM services.

### P1 — Week 2 (performance)

6. Debounce MC WebSocket refresh.
7. Single `AGENT_INTERVALS` source.
8. Merge slippage degradation logic (execution_quality owns, research reads flag).
9. Research queue dedup by `(finding_type, title_hash)`.

### P2 — Week 3 (memory + bus)

10. Migration: `mission_snapshots`, `agent_memory`, `agent_action_log`.
11. Redis `jcm:agent_bus` + orchestrator module.
12. Publish or remove `jcm:system_state`.

### P3 — Week 4 (safety + scale)

13. Agent orchestrator guardrails.
14. WebSocket auth (session token from MC login).
15. Load test harness + 10× ingest script.
16. Parallel ingest pipeline where safe.

---

## Security report (summary)

| Control | Status | Action |
|---------|--------|--------|
| BSv3.2 write isolation | ✅ | Maintain; add orchestrator allowlist |
| Webhook HMAC/secret | ✅ | Rotate periodically |
| API key on mutating routes | ✅ | Keep |
| MC Basic auth | ✅ | Consider session JWT |
| WebSocket open | ✅ | HMAC token via `POST /mission-control/ws-token` |
| Secrets in .env on VPS | ✅ | Never commit; audit `vps-status-check` |
| Agent outbound URLs | ✅ | `is_allowed_outbound_url()` on infra remediation |
| Output validation | ✅ | Briefing vs snapshot + rogue text scan |

---

## Performance report (summary)

| Metric | Current (est.) | Target |
|--------|----------------|--------|
| Live-tick DB queries | ~15+ / 5s | 0–1 (snapshot) |
| CEO briefing builds / day | ~288 | 1–2 |
| MC full refresh requests | 14 / 45s | 14 (unchanged) but lighter tick |
| Research SQL / 2h cycle | ~28+ | <10 |
| Scheduler RAM | 1 Python process | Same; optional 2nd for heavy agents |

---

## Optimization report (summary)

**Highest ROI, lowest risk:** live-tick split + briefing cache + scheduler/NSSM consolidation. These alone move JCM from "fragile dashboard" to "institutional ops surface" without touching trading logic.

**Do not do yet:** LLM reasoning chains per agent (cost, hallucination risk); new agents; auto-remediation without human approval for BSv3.2.

---

## Implementation plan checklist

- [x] Phase 0: Ops + monitoring (P0 items 3–5)
- [x] Phase 1: Performance (P0 items 1–2, P1 items 6–9)
- [x] Phase 2: Memory + messaging (P2)
- [x] Phase 3: Safety + scale (P3)
- [ ] Executive sign-off after load test
- [ ] Update `docs/ARCHITECTURE.md` with bus + memory diagrams

---

## Canvas

Interactive summary: open **jcm-institutional-optimization** canvas in Cursor (Charts, phases, security table).

---

## Implemented (institutional v1)

| Feature | Module |
|---------|--------|
| Lightweight `/dashboard/live-tick` | `build_live_tick()` + Redis mission snapshot |
| Briefing once per day (cached) | `CeoCopilotAgent.generate_daily_briefing(force=)` |
| CEO interval = overview only | `ceo_copilot.run_cycle()` |
| Agent health API | `GET /agents/health` |
| Unified agent registry | `app/services/agent_registry.py` |
| Orchestrator + priority bus channel | `agent_orchestrator.py`, `jcm:agent_bus` |
| Prometheus gauge updates | `update_operational_gauges()` |
| Skip idle ingest-agent cycles | `agent_scheduler` + `mark_ingest_activity` |
| Research queue dedup | `research_evolution._queue_for_review` |
| System state Redis publish | `quant_memory.record_system_state` |
| No live infra probe in briefing context | `executive_briefing/context.py` |
| MC agent health + WS debounce | `mission-control.html` |

**Deploy VPS:** `powershell -File scripts\vps-deploy-institutional.ps1` then `scripts\vps-ensure-agent-scheduler.ps1`

### Phase 3 (institutional v2)

| Feature | Module |
|---------|--------|
| WebSocket HMAC auth | `ws_auth.py`, `websocket.py`, `POST /mission-control/ws-token` |
| Agent guardrails | `agent_guard.py` — forbidden actions, URL allowlist, rogue scan |
| Action audit trail | `GET /dashboard/audit-trail`, Redis `jcm:action_audit` |
| Parallel trade ingest | `event_pipeline.py` — `asyncio.gather` on explain + execution |
| Infra remediation limits | `reserve_remediation_slot()`, outbound URL checks |
| Briefing validation | `validate_briefing_against_snapshot()` in CEO copilot |
| Load test harness | `scripts/load-test-ingest.py` (10× concurrency default) |
| MC audit UI + WS token | `mission-control.html` Agents tab |

**Deploy Phase 3:** `powershell -File scripts\vps-deploy-phase3.ps1`

**Load test (from machine with API access):**
`$env:EVENT_WEBHOOK_SECRET='...'; python scripts/load-test-ingest.py --base http://104.194.140.203:8000 --count 100`

---

*This plan preserves all nine agents and BSv3.2 production strategy while upgrading supervisory intelligence, reliability, and executive visibility.*
