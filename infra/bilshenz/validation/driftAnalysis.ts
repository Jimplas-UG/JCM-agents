import * as fs from 'node:fs';
import * as path from 'node:path';

import type { DriftMetrics, ForwardDemoEvent, LivePeriodStats, SimBaseline30d } from './types';

const PIP = 0.1;

type JournalRow = {
  out?: string;
  dir?: string;
  time?: string;
  entry?: number;
  exitPrice?: number;
};

function pf(grossProfit: number, grossLoss: number): number {
  return grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? 99 : 0;
}

/** MT5 bridge often reports XAU spread in points (~10× pips). Normalize for audit. */
export function normalizeSpreadPips(pips: number): number {
  if (pips <= 0) return 0;
  if (pips > 12) return pips / 10;
  return pips;
}

function loadJournalRows(backendRoot?: string): JournalRow[] {
  if (!backendRoot) return [];
  const journalPath = path.join(backendRoot, 'validation', 'data', 'forward-demo-journal.json');
  if (!fs.existsSync(journalPath)) return [];
  try {
    const raw = fs.readFileSync(journalPath, 'utf8').replace(/^\uFEFF/, '');
    const j = JSON.parse(raw) as { rows?: JournalRow[] };
    return j.rows ?? [];
  } catch {
    return [];
  }
}

function journalOutcomeStats(rows: JournalRow[]): {
  closed: number;
  wins: number;
  losses: number;
  winRatePct: number;
} {
  const closedRows = rows.filter((r) => r.out && r.out !== 'OPEN');
  let wins = 0;
  let lossUnits = 0;
  for (const r of closedRows) {
    if (r.out === 'WIN') wins += 1;
    else if (r.out === 'LOSS') lossUnits += 1;
    else if (r.out === 'HALF_LOSS') lossUnits += 0.5;
    else if (r.out === 'HALF_WIN') wins += 0.5;
    else lossUnits += 1;
  }
  const closed = wins + lossUnits;
  const winRatePct = closed > 0 ? (wins / closed) * 100 : 0;
  return { closed: closedRows.length, wins, losses: lossUnits, winRatePct };
}

/** Aggregate live forward-demo log + journal outcomes (fills for execution, journal for WR). */
export function liveStatsFromEvents(
  events: ForwardDemoEvent[],
  startEquity = 1000,
  backendRoot?: string
): LivePeriodStats {
  const fills = events.filter((e) => e.type === 'ORDER_FILL');
  const equities = events.filter((e) => e.type === 'EQUITY_SNAPSHOT' && e.equityUsd != null);
  const rejected = events.filter((e) => e.type === 'ORDER_REJECTED').length;
  const missed = events.filter((e) => e.type === 'MISSED_TRADE').length;
  const mismatches = events.filter((e) => e.type === 'EXECUTION_MISMATCH').length;

  const journalStats = journalOutcomeStats(loadJournalRows(backendRoot));
  const useJournal = journalStats.closed > 0;
  const wins = useJournal ? journalStats.wins : 0;
  const losses = useJournal ? journalStats.losses : 0;
  const winRatePct = useJournal ? journalStats.winRatePct : 0;

  const startEq = equities[0]?.equityUsd ?? startEquity;
  const endEq = equities[equities.length - 1]?.equityUsd ?? startEq;
  let peak = startEq;
  let maxDd = 0;
  for (const e of equities) {
    const eq = e.equityUsd!;
    if (eq > peak) peak = eq;
    maxDd = Math.max(maxDd, peak - eq);
  }

  const slips = fills.map((f) => f.slippagePips ?? 0);
  const spreads = fills
    .map((f) => normalizeSpreadPips(f.spreadAtExecutionPips ?? 0))
    .filter((x) => x > 0);
  const latencies = fills.map((f) => f.latencyMs ?? 0).filter((x) => x > 0);

  const netPnlUsd = endEq - startEq;
  const grossProfit = netPnlUsd > 0 ? netPnlUsd : 0;
  const grossLoss = netPnlUsd < 0 ? Math.abs(netPnlUsd) : 0;

  return {
    trades: fills.length,
    wins: Math.round(wins * 10) / 10,
    losses: Math.round(losses * 10) / 10,
    winRatePct,
    profitFactor: pf(grossProfit, grossLoss),
    grossProfit,
    grossLoss,
    netPnlUsd,
    startEquity: startEq,
    endEquity: endEq,
    maxDrawdownUsd: maxDd,
    avgSlippagePips: slips.length ? slips.reduce((a, b) => a + b, 0) / slips.length : 0,
    maxSlippagePips: slips.length ? Math.max(...slips) : 0,
    avgSpreadPips: spreads.length ? spreads.reduce((a, b) => a + b, 0) / spreads.length : 0,
    avgLatencyMs: latencies.length ? latencies.reduce((a, b) => a + b, 0) / latencies.length : 0,
    rejectedOrders: rejected,
    missedTrades: missed,
    executionMismatches: mismatches,
  };
}

export function computeDrift(sim: SimBaseline30d, live: LivePeriodStats): DriftMetrics {
  const winRateDriftPct = live.winRatePct - sim.winRatePct;
  const pfDriftPct = sim.profitFactor > 0 ? ((live.profitFactor - sim.profitFactor) / sim.profitFactor) * 100 : 0;
  const simDaily = sim.netPct / sim.windowDays;
  const liveDaily = live.startEquity > 0 ? (live.netPnlUsd / live.startEquity / Math.max(1, live.trades)) * 100 * 30 : 0;
  const returnDriftPct = liveDaily - simDaily * 30;
  const tradeCountDriftPct =
    sim.trades > 0 ? ((live.trades - sim.trades) / sim.trades) * 100 : live.trades > 0 ? 100 : 0;
  const slippageVsSimPips = live.avgSlippagePips - sim.slippagePipsPerSide * 2;
  return {
    winRateDriftPct,
    pfDriftPct,
    returnDriftPct,
    tradeCountDriftPct,
    slippageVsSimPips,
  };
}

/** Overall simulation vs live variance (0–100+, lower is better alignment). */
export function simVsLiveVariancePct(drift: DriftMetrics, sim: SimBaseline30d, live: LivePeriodStats): number {
  const wr = Math.abs(drift.winRateDriftPct);
  const pf = Math.abs(drift.pfDriftPct);
  const ret = Math.abs(drift.returnDriftPct);
  const slip = Math.abs(drift.slippageVsSimPips) * 8;
  const rejectRate =
    (live.rejectedOrders / Math.max(1, live.trades + live.rejectedOrders)) * 100;
  const raw = wr * 1.2 + pf * 0.4 + Math.min(40, ret) + slip + rejectRate;
  if (live.trades === 0) return -1;
  return Math.round(Math.min(100, raw) * 10) / 10;
}
