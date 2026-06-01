# Forward vs Simulation — Side-by-Side Report

Generated: 2026-06-01T15:04:45.108713+00:00
Forward session start: 2026-05-21T01:42:29+00:00

## Executive summary

The **strategy engine is aligned** (same frozen BSv3.2, P2 signals fire in live). Performance diverges mainly because **most signals never become fills** (infra/execution), not because the signal logic changed.

## Headline metrics

| Metric | Sim (30d backtest) | Sim (rolling 30d) | Live forward | Gap |
|--------|-------------------|-------------------|--------------|-----|
| Trades | 53 | 46 | 5 fills / 4 closed | **-41 fills** |
| Win rate | 71.7% | 63.0% | 25.0% (journal) | **-38.0pp** |
| Profit factor | 4.83 | 3.03 | n/a (tiny sample) | — |
| Spread (assumed / measured) | 3.08p | 3.08p | 3.08p norm | see note below |

## Signal funnel (live session)

- **Signals:** 13
- **Order intents:** 13
- **Fills:** 5 (38.5% of signals)
- **Rejected:** 8 (38.1% of attempts)

### Rejection root causes

- **AutoTrading disabled (MT5):** 4
- **MT5 API not connected:** 2
- **Invalid stops (broker):** 2

## Trade-by-trade (journal = sim-style outcomes)

| Time (UTC) | Dir | Setup | Outcome | Entry | Exit |
|------------|-----|-------|---------|-------|------|
| 2026-06-01 11:00 | SELL | P2 | **OPEN** | 4510.385 | — |
| 2026-06-01 09:30 | SELL | P2 | **HALF_LOSS** | 4496.118 | 4501.254 |
| 2026-06-01 07:30 | SELL | P2 | **LOSS** | 4502.921 | — |
| 2026-05-29 09:00 | BUY | P2 | **WIN** | 4529.003 | — |
| 2026-05-28 23:30 | SELL | P2 | **HALF_LOSS** | 4494.974 | 4496.052 |

## Live fills (execution log)

| Time (UTC) | Side | Ticket | Fill | Spread (raw→norm) | Latency ms |
|------------|------|--------|------|-------------------|------------|
| 2026-06-01 11:30:01 | SELL | 2798751277 | 4510.619 | 30.8→3.08p | 172.9 |
| 2026-06-01 10:00:44 | SELL | 2798457999 | 4498.202 | 30.8→3.08p | 176.7 |
| 2026-06-01 08:00:43 | SELL | 2798071579 | 4502.519 | 30.8→3.08p | 186.9 |
| 2026-05-29 09:31:07 | BUY | 2793167761 | 4528.878 | 30.8→3.08p | 180.2 |
| 2026-05-29 00:00:45 | SELL | 2792061068 | 4494.47 | 30.8→3.08p | 206.5 |

## Weakness ranking (fix priority)

1. **Execution availability (CRITICAL)** — 8/13 signals rejected: AutoTrading off, MT5 disconnects, invalid stops. Sim assumes every signal fills; live does not.
2. **Low sample (HIGH)** — Only 5 fills in ~11 days vs ~46 sim trades in 30d. Cannot validate win rate or PF until fill rate recovers.
3. **Audit metrics bug (FIXED in repo)** — `liveStatsFromEvents` treated all fills as wins; spread 30.8 is points not pips (~3.08p). Inflated false 100% WR in audit.
4. **Outcome drift (MEDIUM)** — Journal WR ~25% on 4 closes vs sim ~63–72%. Needs more trades after execution fixes before judging edge.
5. **JCM close pipeline (MEDIUM)** — Mission Control still shows opens; trade_closed webhooks deployed but historical closes not backfilled.

## Recommended fixes (no strategy logic changes)

- Enable **Algo Trading** on Exness MT5 terminal (fixes retcode 10027).
- Ensure **MT5 API + forward bot** start together (`Bilshenz-MT5-API-Sys` then `Bilshenz-ForwardBot-Sys`).
- Review **Invalid stops** (10016) — SL distance vs broker stop level on XAU.
- Deploy validation patch: journal-based WR + spread normalization.
- Continue forward demo to **20+ fills** before comparing to sim again.
