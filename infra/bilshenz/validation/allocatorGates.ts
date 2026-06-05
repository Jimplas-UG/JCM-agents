import * as fs from 'node:fs';

import type { ExtendedLiveMetrics } from './institutionalMetrics';
import type { ReconciliationResult } from './tradeReconciliation';
import type { StressReadiness } from './stressChecks';
import type { SimBaseline30d } from './types';

export type AllocatorGate = {
  code: string;
  label: string;
  pass: boolean;
  required: boolean;
  current: string;
  target: string;
  weight: number;
};

export type AllocatorReadinessReport = {
  checkReady: boolean;
  progressScore: number;
  tier: 'not_ready' | 'building' | 'allocator_candidate' | 'allocator_ready';
  gates: AllocatorGate[];
  blockers: string[];
  nextMilestones: string[];
};

export type ResearchAttestation = {
  ok: boolean;
  path: string | null;
  profitFactor: number | null;
  trades: number | null;
  winRatePct: number | null;
  netPct: number | null;
  generatedAt: string | null;
};

export type TcaSummary = {
  avgSlippagePips: number;
  maxSlippagePips: number;
  avgLatencyMs: number;
  rejectPct: number;
  simSlippagePips: number;
  slippageVsSimRatio: number;
  pass: boolean;
};

const GATES = {
  LIVE_CLOSED: 50,
  LIVE_DAYS: 90,
  FILL_PCT: 90,
  RESEARCH_PF: 1.5,
  RESEARCH_TRADES: 100,
  TCA_SLIPPAGE_RATIO: 2.0,
} as const;

function parseResearchReport(text: string): Partial<ResearchAttestation> {
  const pf = text.match(/Profit factor[^:]*:\s*([\d.]+)/i);
  const trades = text.match(/Closed in window:\s*(\d+)/i);
  const wr = text.match(/Win rate \(closed\):\s*([\d.]+)%/i);
  const net = text.match(/Net PnL:[^+]*\+?([-\d.]+)%/i) || text.match(/\((\+[\d.]+)%\)/);
  return {
    profitFactor: pf ? parseFloat(pf[1]!) : null,
    trades: trades ? parseInt(trades[1]!, 10) : null,
    winRatePct: wr ? parseFloat(wr[1]!) : null,
    netPct: net ? parseFloat(net[1]!.replace('+', '')) : null,
  };
}

export function loadResearchAttestation(paths: string[]): ResearchAttestation {
  for (const p of paths) {
    try {
      if (!fs.existsSync(p)) continue;
      const text = fs.readFileSync(p, 'utf8');
      const parsed = parseResearchReport(text);
      const ok =
        (parsed.profitFactor ?? 0) >= GATES.RESEARCH_PF &&
        (parsed.trades ?? 0) >= GATES.RESEARCH_TRADES;
      return {
        ok,
        path: p,
        profitFactor: parsed.profitFactor ?? null,
        trades: parsed.trades ?? null,
        winRatePct: parsed.winRatePct ?? null,
        netPct: parsed.netPct ?? null,
        generatedAt: fs.statSync(p).mtime.toISOString(),
      };
    } catch {
      continue;
    }
  }
  return {
    ok: false,
    path: null,
    profitFactor: null,
    trades: null,
    winRatePct: null,
    netPct: null,
    generatedAt: null,
  };
}

export function buildTcaSummary(
  live: ExtendedLiveMetrics,
  sim: SimBaseline30d,
  recentRejectPct?: number
): TcaSummary {
  const simSlip = sim.slippagePipsPerSide ?? 0.4;
  const ratio = simSlip > 0 ? live.avgSlippagePips / simSlip : live.avgSlippagePips;
  const rejectPct = recentRejectPct ?? live.orderRejectPct;
  return {
    avgSlippagePips: live.avgSlippagePips,
    maxSlippagePips: live.maxSlippagePips,
    avgLatencyMs: live.avgLatencyMs,
    rejectPct,
    simSlippagePips: simSlip,
    slippageVsSimRatio: Math.round(ratio * 100) / 100,
    pass: ratio <= GATES.TCA_SLIPPAGE_RATIO && rejectPct < 15,
  };
}

export function computeAllocatorReadiness(args: {
  live: ExtendedLiveMetrics;
  sim: SimBaseline30d;
  reconciliation: ReconciliationResult;
  stress: StressReadiness;
  research: ResearchAttestation;
  tca: TcaSummary;
  liveDays: number;
  staleJcmOpens: number;
  killSwitchEnforced: boolean;
}): AllocatorReadinessReport {
  const { live, reconciliation, stress, research, tca, liveDays, staleJcmOpens, killSwitchEnforced } =
    args;

  const gates: AllocatorGate[] = [
    {
      code: 'LIVE_CLOSED_TRADES',
      label: 'Live closed trade count',
      pass: live.closedTrades >= GATES.LIVE_CLOSED,
      required: true,
      current: String(live.closedTrades),
      target: `>=${GATES.LIVE_CLOSED}`,
      weight: 0.2,
    },
    {
      code: 'LIVE_TRACK_DAYS',
      label: 'Clean forward track record',
      pass: liveDays >= GATES.LIVE_DAYS,
      required: true,
      current: `${liveDays}d`,
      target: `>=${GATES.LIVE_DAYS}d`,
      weight: 0.15,
    },
    {
      code: 'SIGNAL_TO_FILL',
      label: 'Signal to fill rate (rolling)',
      pass: live.signalToFillPct >= GATES.FILL_PCT,
      required: true,
      current: `${live.signalToFillPct}%`,
      target: `>=${GATES.FILL_PCT}%`,
      weight: 0.15,
    },
    {
      code: 'LEDGER_RECONCILIATION',
      label: 'JSONL / journal reconciliation',
      pass: reconciliation.ok,
      required: true,
      current: `${reconciliation.matchPct}%`,
      target: '100% aligned',
      weight: 0.1,
    },
    {
      code: 'JCM_STALE_OPENS',
      label: 'Zero stale JCM open records',
      pass: staleJcmOpens === 0,
      required: true,
      current: String(staleJcmOpens),
      target: '0',
      weight: 0.08,
    },
    {
      code: 'RESEARCH_ATTESTATION',
      label: '12mo realistic MT5 backtest on file',
      pass: research.ok,
      required: true,
      current: research.profitFactor != null ? `PF ${research.profitFactor}` : 'missing',
      target: `PF>=${GATES.RESEARCH_PF}, trades>=${GATES.RESEARCH_TRADES}`,
      weight: 0.12,
    },
    {
      code: 'TCA_QUALITY',
      label: 'Transaction cost vs sim',
      pass: tca.pass,
      required: true,
      current: `${tca.slippageVsSimRatio}x slippage, ${tca.rejectPct}% reject`,
      target: `<${GATES.TCA_SLIPPAGE_RATIO}x slippage, <15% reject`,
      weight: 0.1,
    },
    {
      code: 'STRESS_OPS',
      label: 'Operational stress checks',
      pass: stress.passCount === stress.checks.length,
      required: true,
      current: `${stress.passCount}/${stress.checks.length}`,
      target: 'all pass',
      weight: 0.05,
    },
    {
      code: 'KILL_SWITCH_LOOP',
      label: 'JCM kill-switch enforces forward halt',
      pass: killSwitchEnforced,
      required: true,
      current: killSwitchEnforced ? 'wired' : 'advisory only',
      target: 'closed-loop halt',
      weight: 0.05,
    },
  ];

  const required = gates.filter((g) => g.required);
  const passed = required.filter((g) => g.pass);
  const progressScore = Math.round(
    gates.reduce((s, g) => s + (g.pass ? g.weight * 100 : 0), 0)
  );
  const checkReady = required.every((g) => g.pass);
  const blockers = required.filter((g) => !g.pass).map((g) => `${g.label}: ${g.current} (need ${g.target})`);

  const nextMilestones: string[] = [];
  if (live.closedTrades < GATES.LIVE_CLOSED) {
    nextMilestones.push(`${GATES.LIVE_CLOSED - live.closedTrades} more closed live trades`);
  }
  if (liveDays < GATES.LIVE_DAYS) {
    nextMilestones.push(`${GATES.LIVE_DAYS - liveDays} more days of clean forward`);
  }
  if (live.signalToFillPct < GATES.FILL_PCT) {
    nextMilestones.push('Run forward stack 24/7 until rolling fill rate >= 90%');
  }
  if (staleJcmOpens > 0) {
    nextMilestones.push('Run allocator pipeline backfill to clear stale JCM opens');
  }
  if (!research.ok) {
    nextMilestones.push('Run realistic MT5 12mo backtest and archive report');
  }

  const tier = checkReady
    ? 'allocator_ready'
    : progressScore >= 70
      ? 'allocator_candidate'
      : progressScore >= 45
        ? 'building'
        : 'not_ready';

  return { checkReady, progressScore, tier, gates, blockers, nextMilestones };
}

export function formatAllocatorReport(args: {
  generatedAt: string;
  report: AllocatorReadinessReport;
  research: ResearchAttestation;
  tca: TcaSummary;
}): string {
  const lines: string[] = [];
  lines.push('JCM / BILSHENZ — ALLOCATOR READINESS (DUE DILIGENCE GATES)');
  lines.push(`Generated: ${args.generatedAt}`);
  lines.push('');
  lines.push(
    `CHECK-READY: ${args.report.checkReady ? 'YES — allocator DD gates passed' : 'NO — not yet check-ready'}`
  );
  lines.push(`Progress: ${args.report.progressScore}/100 (${args.report.tier})`);
  lines.push('');
  lines.push('── Hard gates (all required for a check) ──');
  for (const g of args.report.gates) {
    lines.push(`  [${g.pass ? 'PASS' : 'FAIL'}] ${g.label}: ${g.current} (target ${g.target})`);
  }
  lines.push('');
  lines.push('── Research attestation ──');
  if (args.research.path) {
    lines.push(
      `  File: ${args.research.path} · PF ${args.research.profitFactor} · ${args.research.trades} trades · WR ${args.research.winRatePct}%`
    );
  } else {
    lines.push('  No realistic MT5 backtest report found');
  }
  lines.push('');
  lines.push('── TCA summary ──');
  lines.push(
    `  Avg slippage ${args.tca.avgSlippagePips.toFixed(2)}p (sim ${args.tca.simSlippagePips}p, ratio ${args.tca.slippageVsSimRatio}x)`
  );
  lines.push(`  Reject ${args.tca.rejectPct}% · Latency ${args.tca.avgLatencyMs.toFixed(0)}ms`);
  if (args.report.blockers.length) {
    lines.push('');
    lines.push('── Blockers ──');
    for (const b of args.report.blockers) lines.push(`  • ${b}`);
  }
  if (args.report.nextMilestones.length) {
    lines.push('');
    lines.push('── Next milestones ──');
    for (const m of args.report.nextMilestones) lines.push(`  • ${m}`);
  }
  return lines.join('\n');
}
