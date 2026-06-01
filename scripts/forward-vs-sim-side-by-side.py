#!/usr/bin/env python3
"""Forward demo vs simulation side-by-side report (observability only)."""

from __future__ import annotations

import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "reports"
LOG_PATH = REPORTS / "forward-demo-log.jsonl"
JOURNAL_PATH = REPORTS / "forward-demo-journal.json"
OUT_PATH = REPORTS / "forward-vs-sim-report.md"

SESSION_START = datetime(2026, 5, 21, 1, 42, 29, tzinfo=timezone.utc)

SIM_30D = {
    "window": "2026-04-21 → 2026-05-21 (frozen backtest)",
    "trades": 53,
    "win_rate_pct": 71.7,
    "profit_factor": 4.83,
    "max_dd_usd": 1819.62,
    "spread_pips": 3.08,
}

SIM_ROLLING = {
    "window": "2026-05-02 → 2026-06-01 (rolling 30d sim)",
    "trades": 46,
    "win_rate_pct": 63.0,
    "profit_factor": 3.03,
    "max_dd_usd": 1652.0,
    "spread_pips": 3.08,
}


def parse_ts(s: str) -> datetime:
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def normalize_spread(pips: float) -> float:
    """MT5 bridge reports XAU spread in points (~10x pips)."""
    if pips <= 0:
        return 0.0
    return pips / 10.0 if pips > 12 else pips


def load_events() -> list[dict]:
    events = []
    with LOG_PATH.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                events.append(json.loads(line))
    return events


def main() -> None:
    events = load_events()
    session = [e for e in events if parse_ts(e["ts"]) >= SESSION_START]

    signals = [e for e in session if e.get("type") == "SIGNAL"]
    fills = [e for e in session if e.get("type") == "ORDER_FILL"]
    rejects = [e for e in session if e.get("type") == "ORDER_REJECTED"]
    intents = [e for e in session if e.get("type") == "ORDER_INTENT"]

    journal = json.loads(JOURNAL_PATH.read_text(encoding="utf-8"))
    rows = journal.get("rows", [])
    closed = [r for r in rows if r.get("out") != "OPEN"]
    wins = sum(1 for r in closed if r.get("out") == "WIN")
    losses = sum(1 for r in closed if r.get("out") == "LOSS")
    half_loss = sum(1 for r in closed if r.get("out") == "HALF_LOSS")
    journal_wr = 100.0 * wins / max(1, len(closed))

    reject_reasons: Counter[str] = Counter()
    for r in rejects:
        rr = str(r.get("rejectReason", ""))
        if "AutoTrading disabled" in rr:
            reject_reasons["AutoTrading disabled (MT5)"] += 1
        elif "not connected" in rr:
            reject_reasons["MT5 API not connected"] += 1
        elif "Invalid stops" in rr:
            reject_reasons["Invalid stops (broker)"] += 1
        else:
            reject_reasons[rr[:55] + ("…" if len(rr) > 55 else "")] += 1

    spreads_raw = [float(f.get("spreadAtExecutionPips") or 0) for f in fills]
    spreads_norm = [normalize_spread(s) for s in spreads_raw if s > 0]

    lines: list[str] = []
    lines.append("# Forward vs Simulation — Side-by-Side Report")
    lines.append("")
    lines.append(f"Generated: {datetime.now(timezone.utc).isoformat()}")
    lines.append(f"Forward session start: {SESSION_START.isoformat()}")
    lines.append("")

    lines.append("## Executive summary")
    lines.append("")
    lines.append(
        "The **strategy engine is aligned** (same frozen BSv3.2, P2 signals fire in live). "
        "Performance diverges mainly because **most signals never become fills** (infra/execution), "
        "not because the signal logic changed."
    )
    lines.append("")

    lines.append("## Headline metrics")
    lines.append("")
    lines.append("| Metric | Sim (30d backtest) | Sim (rolling 30d) | Live forward | Gap |")
    lines.append("|--------|-------------------|-------------------|--------------|-----|")
    lines.append(
        f"| Trades | {SIM_30D['trades']} | {SIM_ROLLING['trades']} | {len(fills)} fills / {len(closed)} closed | "
        f"**-{SIM_ROLLING['trades'] - len(fills)} fills** |"
    )
    lines.append(
        f"| Win rate | {SIM_30D['win_rate_pct']:.1f}% | {SIM_ROLLING['win_rate_pct']:.1f}% | "
        f"{journal_wr:.1f}% (journal) | **{journal_wr - SIM_ROLLING['win_rate_pct']:+.1f}pp** |"
    )
    lines.append(
        f"| Profit factor | {SIM_30D['profit_factor']:.2f} | {SIM_ROLLING['profit_factor']:.2f} | "
        f"n/a (tiny sample) | — |"
    )
    lines.append(
        f"| Spread (assumed / measured) | {SIM_30D['spread_pips']:.2f}p | {SIM_ROLLING['spread_pips']:.2f}p | "
        f"{(sum(spreads_norm)/len(spreads_norm)) if spreads_norm else 0:.2f}p norm | "
        f"see note below |"
    )
    lines.append("")

    lines.append("## Signal funnel (live session)")
    lines.append("")
    lines.append(f"- **Signals:** {len(signals)}")
    lines.append(f"- **Order intents:** {len(intents)}")
    lines.append(f"- **Fills:** {len(fills)} ({100*len(fills)/max(1,len(signals)):.1f}% of signals)")
    lines.append(f"- **Rejected:** {len(rejects)} ({100*len(rejects)/max(1,len(signals)+len(rejects)):.1f}% of attempts)")
    lines.append("")
    lines.append("### Rejection root causes")
    lines.append("")
    for reason, count in reject_reasons.most_common():
        lines.append(f"- **{reason}:** {count}")
    lines.append("")

    lines.append("## Trade-by-trade (journal = sim-style outcomes)")
    lines.append("")
    lines.append("| Time (UTC) | Dir | Setup | Outcome | Entry | Exit |")
    lines.append("|------------|-----|-------|---------|-------|------|")
    for r in sorted(rows, key=lambda x: x.get("time", ""), reverse=True):
        lines.append(
            f"| {r.get('time','')[:16].replace('T',' ')} | {r.get('dir','')} | {r.get('type','')} | "
            f"**{r.get('out','')}** | {r.get('entry','')} | {r.get('exitPrice','—')} |"
        )
    lines.append("")

    lines.append("## Live fills (execution log)")
    lines.append("")
    lines.append("| Time (UTC) | Side | Ticket | Fill | Spread (raw→norm) | Latency ms |")
    lines.append("|------------|------|--------|------|-------------------|------------|")
    for f in sorted(fills, key=lambda x: x.get("ts", ""), reverse=True):
        sp = float(f.get("spreadAtExecutionPips") or 0)
        lines.append(
            f"| {f.get('ts','')[:19].replace('T',' ')} | {f.get('side','')} | {f.get('ticket','')} | "
            f"{f.get('actualFill','')} | {sp:.1f}→{normalize_spread(sp):.2f}p | {f.get('latencyMs','')} |"
        )
    lines.append("")

    lines.append("## Weakness ranking (fix priority)")
    lines.append("")
    lines.append(
        "1. **Execution availability (CRITICAL)** — 8/13 signals rejected: AutoTrading off, MT5 disconnects, invalid stops. "
        "Sim assumes every signal fills; live does not."
    )
    lines.append(
        "2. **Low sample (HIGH)** — Only 5 fills in ~11 days vs ~46 sim trades in 30d. "
        "Cannot validate win rate or PF until fill rate recovers."
    )
    lines.append(
        "3. **Audit metrics bug (FIXED in repo)** — `liveStatsFromEvents` treated all fills as wins; "
        "spread 30.8 is points not pips (~3.08p). Inflated false 100% WR in audit."
    )
    lines.append(
        "4. **Outcome drift (MEDIUM)** — Journal WR ~25% on 4 closes vs sim ~63–72%. "
        "Needs more trades after execution fixes before judging edge."
    )
    lines.append(
        "5. **JCM close pipeline (MEDIUM)** — Mission Control still shows opens; "
        "trade_closed webhooks deployed but historical closes not backfilled."
    )
    lines.append("")

    lines.append("## Recommended fixes (no strategy logic changes)")
    lines.append("")
    lines.append("- Enable **Algo Trading** on Exness MT5 terminal (fixes retcode 10027).")
    lines.append("- Ensure **MT5 API + forward bot** start together (`Bilshenz-MT5-API-Sys` then `Bilshenz-ForwardBot-Sys`).")
    lines.append("- Review **Invalid stops** (10016) — SL distance vs broker stop level on XAU.")
    lines.append("- Deploy validation patch: journal-based WR + spread normalization.")
    lines.append("- Continue forward demo to **20+ fills** before comparing to sim again.")
    lines.append("")

    OUT_PATH.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {OUT_PATH}")


if __name__ == "__main__":
    main()
