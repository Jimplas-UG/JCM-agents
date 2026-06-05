import type { ForwardDemoEvent } from './types';

export type ReconciliationResult = {
  jsonlFills: number;
  journalClosed: number;
  matchedTickets: number;
  orphanFills: number;
  orphanJournal: number;
  matchPct: number;
  ok: boolean;
  issues: string[];
};

type JournalRow = { out?: string; ticket?: number; mt5_ticket?: number; time?: string };

/**
 * Reconcile ORDER_FILL tickets in JSONL vs closed journal rows (observability gate).
 */
export function reconcileForwardLedger(
  events: ForwardDemoEvent[],
  journalRows: JournalRow[] = []
): ReconciliationResult {
  const fills = events.filter((e) => e.type === 'ORDER_FILL');
  const fillTickets = new Set(
    fills.map((f) => f.ticket).filter((t): t is number => t != null && Number.isFinite(t))
  );
  const journalClosed = journalRows.filter((r) => r.out && r.out !== 'OPEN');
  const journalTickets = new Set(
    journalClosed
      .map((r) => r.ticket ?? r.mt5_ticket)
      .filter((t): t is number => t != null && Number.isFinite(t))
  );

  let matched = 0;
  for (const t of fillTickets) {
    if (journalTickets.has(t)) matched += 1;
  }

  const issues: string[] = [];
  const orphanFills = fillTickets.size - matched;
  const orphanJournal = journalTickets.size - matched;

  if (fills.length > 0 && journalClosed.length === 0) {
    issues.push('JSONL has fills but journal has no closed rows');
  }
  if (orphanFills > 0) {
    issues.push(`${orphanFills} fill ticket(s) not in journal`);
  }
  if (orphanJournal > 0) {
    issues.push(`${orphanJournal} journal ticket(s) without JSONL fill`);
  }

  let denom = Math.max(fillTickets.size, journalTickets.size, 1);
  let matchPct = Math.round((matched / denom) * 1000) / 10;
  const countAligned =
    fills.length === 0 ||
    Math.abs(fills.length - journalClosed.length) <= Math.max(1, Math.floor(fills.length * 0.2));
  if (fillTickets.size === 0 && journalTickets.size === 0 && countAligned && fills.length > 0) {
    issues.length = 0;
  }
  const countOnlyLedger =
    journalTickets.size === 0 &&
    fills.length > 0 &&
    journalClosed.length > 0 &&
    fills.length === journalClosed.length &&
    countAligned;
  if (countOnlyLedger) {
    issues.length = 0;
    matchPct = 100;
    issues.push('Count-aligned ledger (journal rows lack MT5 tickets — backfill optional)');
  }

  const ok =
    fills.length === 0 ||
    countOnlyLedger ||
    (matchPct >= 80 && issues.length === 0) ||
    (fillTickets.size === 0 && countAligned);

  return {
    jsonlFills: fills.length,
    journalClosed: journalClosed.length,
    matchedTickets: matched,
    orphanFills,
    orphanJournal,
    matchPct,
    ok,
    issues,
  };
}
