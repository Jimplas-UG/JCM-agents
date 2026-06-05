import type { ForwardDemoEvent, LivePeriodStats } from './types';

type JournalRow = {
  out?: string;
  dir?: string;
  time?: string;
  entry?: number;
  exitPrice?: number;
  pnlUsd?: number;
};

export type ExtendedLiveMetrics = LivePeriodStats & {
  signals: number;
  orderIntents: number;
  signalToFillPct: number;
  orderRejectPct: number;
  sharpeRatio: number | null;
  sortinoRatio: number | null;
  expectancyUsd: number | null;
  avgTradeDurationHours: number | null;
  closedTrades: number;
};

function journalRows(rows: JournalRow[]) {
  return rows.filter((r) => r.out && r.out !== 'OPEN');
}

function parseTimeMs(t?: string): number | null {
  if (!t) return null;
  const ms = Date.parse(t);
  return Number.isFinite(ms) ? ms : null;
}

/** Sharpe/Sortino from equity snapshot series (hourly-ish). Annualized sqrt(252). */
function riskAdjustedFromEquity(events: ForwardDemoEvent[]): {
  sharpe: number | null;
  sortino: number | null;
} {
  const eq = events
    .filter((e) => e.type === 'EQUITY_SNAPSHOT' && e.equityUsd != null)
    .sort((a, b) => a.tsMs - b.tsMs);
  if (eq.length < 5) return { sharpe: null, sortino: null };

  const rets: number[] = [];
  for (let i = 1; i < eq.length; i++) {
    const prev = eq[i - 1]!.equityUsd!;
    const cur = eq[i]!.equityUsd!;
    if (prev > 0) rets.push((cur - prev) / prev);
  }
  if (rets.length < 3) return { sharpe: null, sortino: null };

  const mean = rets.reduce((a, b) => a + b, 0) / rets.length;
  const variance =
    rets.reduce((s, r) => s + (r - mean) ** 2, 0) / Math.max(1, rets.length - 1);
  const std = Math.sqrt(variance);
  const ann = Math.sqrt(252);
  const sharpe = std > 1e-9 ? (mean / std) * ann : null;

  const downside = rets.filter((r) => r < 0);
  if (downside.length < 2) return { sharpe, sortino: sharpe };
  const dMean = downside.reduce((a, b) => a + b, 0) / downside.length;
  const dVar =
    downside.reduce((s, r) => s + (r - dMean) ** 2, 0) / Math.max(1, downside.length - 1);
  const dStd = Math.sqrt(dVar);
  const sortino = dStd > 1e-9 ? (mean / dStd) * ann : null;
  return { sharpe, sortino };
}

function expectancyFromJournal(rows: JournalRow[]): number | null {
  const closed = journalRows(rows);
  if (closed.length < 3) return null;
  const pnls: number[] = [];
  for (const r of closed) {
    if (typeof r.pnlUsd === 'number' && Number.isFinite(r.pnlUsd)) {
      pnls.push(r.pnlUsd);
      continue;
    }
    if (r.entry != null && r.exitPrice != null) {
      const dir = (r.dir ?? '').toUpperCase();
      const diff = r.exitPrice - r.entry;
      pnls.push(dir === 'SELL' || dir === 'SHORT' ? -diff * 10 : diff * 10);
    }
  }
  if (pnls.length < 3) return null;
  return pnls.reduce((a, b) => a + b, 0) / pnls.length;
}

function avgDurationHours(rows: JournalRow[]): number | null {
  const times = rows
    .map((r) => parseTimeMs(r.time))
    .filter((t): t is number => t != null)
    .sort((a, b) => a - b);
  if (times.length < 2) return null;
  const spanMs = times[times.length - 1]! - times[0]!;
  const closed = journalRows(rows).length || 1;
  return spanMs / closed / 3600000;
}

export function extendLiveMetrics(
  base: LivePeriodStats,
  events: ForwardDemoEvent[],
  journal: JournalRow[] = []
): ExtendedLiveMetrics {
  const signals = events.filter((e) => e.type === 'SIGNAL').length;
  const intents = events.filter((e) => e.type === 'ORDER_INTENT').length;
  const attempts = base.trades + base.rejectedOrders;
  const signalToFillPct = signals > 0 ? (base.trades / signals) * 100 : base.trades > 0 ? 100 : 0;
  const orderRejectPct = attempts > 0 ? (base.rejectedOrders / attempts) * 100 : 0;
  const { sharpe, sortino } = riskAdjustedFromEquity(events);
  const closed = journalRows(journal).length;
  const expectancy = expectancyFromJournal(journal);
  const avgHours = avgDurationHours(journal);

  return {
    ...base,
    signals,
    orderIntents: intents,
    signalToFillPct: Math.round(signalToFillPct * 10) / 10,
    orderRejectPct: Math.round(orderRejectPct * 10) / 10,
    sharpeRatio: sharpe != null ? Math.round(sharpe * 100) / 100 : null,
    sortinoRatio: sortino != null ? Math.round(sortino * 100) / 100 : null,
    expectancyUsd: expectancy != null ? Math.round(expectancy * 100) / 100 : null,
    avgTradeDurationHours: avgHours != null ? Math.round(avgHours * 10) / 10 : null,
    closedTrades: closed,
  };
}
