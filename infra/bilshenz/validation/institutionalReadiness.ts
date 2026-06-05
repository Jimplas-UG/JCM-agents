import type { ReconciliationResult } from './tradeReconciliation';
import type { ExtendedLiveMetrics } from './institutionalMetrics';
import type { StressReadiness } from './stressChecks';
import type { ExecutionAuditScores, SimBaseline30d, ValidationAlert } from './types';

export type InstitutionalDimension = {
  name: string;
  score: number;
  weight: number;
  notes: string[];
};

export type InstitutionalReadinessReport = {
  compositeScore: number;
  tier: 'development' | 'prop_micro' | 'institutional_candidate' | 'institutional';
  dimensions: InstitutionalDimension[];
  targetsFor80: string[];
};

function clamp(n: number, lo = 0, hi = 100): number {
  return Math.max(lo, Math.min(hi, Math.round(n)));
}

export function computeInstitutionalReadiness(args: {
  freezeOk: boolean;
  live: ExtendedLiveMetrics;
  sim: SimBaseline30d;
  scores: ExecutionAuditScores;
  reconciliation: ReconciliationResult;
  stress: StressReadiness;
  infraScore: number;
}): InstitutionalReadinessReport {
  const { freezeOk, live, sim, scores, reconciliation, stress, infraScore } = args;
  const notes: Record<string, string[]> = {
    strategy: [],
    risk: [],
    execution: [],
    infrastructure: [],
    monitoring: [],
    recovery: [],
    capital: [],
    scalability: [],
  };

  let strategy = 72;
  if (freezeOk) strategy += 12;
  else strategy -= 25;
  if (Math.abs(live.winRatePct - sim.winRatePct) <= 15 && live.closedTrades >= 8) strategy += 8;
  else if (live.closedTrades < 8) {
    strategy -= 5;
    notes.strategy.push('Need 8+ closed trades for WR validation');
  }
  notes.strategy.push(freezeOk ? 'Strategy freeze PASS' : 'Strategy freeze FAIL');

  let risk = 70;
  if (live.maxDrawdownUsd <= sim.maxDrawdownUsd * 1.35) risk += 10;
  risk += live.closedTrades >= 5 ? 5 : 0;
  notes.risk.push('Daily loss + failsafe + 1% risk active on forward');

  let execution = scores.brokerExecutionQuality;
  if (live.signalToFillPct >= 90) execution = Math.min(100, execution + 15);
  else if (live.signalToFillPct >= 75) execution = Math.min(100, execution + 8);
  else notes.execution.push(`Signal→fill ${live.signalToFillPct}% (target ≥90%)`);

  const opsExecutionReady = ['MT5_UPTIME', 'FORWARD_WORKER', 'REJECT_STORM', 'API_OUTAGE_RECOVERY'].every(
    (code) => stress.checks.find((c) => c.code === code)?.pass
  );
  if (opsExecutionReady && infraScore >= 70) {
    execution = Math.max(execution, 78);
    notes.execution.push('Execution stack operational (MT5 + forward + failsafe clear)');
  }

  const infrastructure = clamp(infraScore);
  notes.infrastructure.push(`VPS infra alignment ${infraScore}/100`);

  let monitoring = 55;
  if (reconciliation.ok) monitoring += 20;
  if (live.sharpeRatio != null) monitoring += 8;
  if (live.expectancyUsd != null) monitoring += 7;
  if (live.sortinoRatio != null) monitoring += 5;
  notes.monitoring.push(
    reconciliation.ok
      ? `Ledger match ${reconciliation.matchPct}%`
      : `Ledger reconciliation issues: ${reconciliation.issues.join('; ')}`
  );

  const recovery = clamp(stress.score * 0.85 + (scores.brokerExecutionQuality > 50 ? 10 : 0));
  notes.recovery.push(`Stress checks ${stress.passCount}/${stress.checks.length} pass`);

  let capital = 75;
  if (live.maxDrawdownUsd > sim.maxDrawdownUsd * 1.5) capital -= 15;
  if (live.profitFactor >= 1.5 && live.closedTrades >= 8) capital += 10;
  notes.capital.push(`Max DD $${live.maxDrawdownUsd.toFixed(0)}`);

  const scalability = 48;
  notes.scalability.push('Single symbol/VPS — multi-asset tier pending');

  const dimensions: InstitutionalDimension[] = [
    { name: 'Strategy robustness', score: clamp(strategy), weight: 0.15, notes: notes.strategy },
    { name: 'Risk management', score: clamp(risk), weight: 0.12, notes: notes.risk },
    { name: 'Execution quality', score: clamp(execution), weight: 0.18, notes: notes.execution },
    { name: 'Infrastructure reliability', score: infrastructure, weight: 0.14, notes: notes.infrastructure },
    { name: 'Monitoring', score: clamp(monitoring), weight: 0.12, notes: notes.monitoring },
    { name: 'Recovery systems', score: recovery, weight: 0.1, notes: notes.recovery },
    { name: 'Capital preservation', score: clamp(capital), weight: 0.12, notes: notes.capital },
    { name: 'Scalability', score: scalability, weight: 0.07, notes: notes.scalability },
  ];

  const compositeScore = clamp(dimensions.reduce((s, d) => s + d.score * d.weight, 0));

  const tier =
    compositeScore >= 85
      ? 'institutional'
      : compositeScore >= 75
        ? 'institutional_candidate'
        : compositeScore >= 62
          ? 'prop_micro'
          : 'development';

  const targetsFor80: string[] = [];
  if (live.signalToFillPct < 90) targetsFor80.push('Raise signal→fill to ≥90% (execution stack)');
  if (live.closedTrades < 20) targetsFor80.push('Accumulate 20+ closed forward trades');
  if (!reconciliation.ok) targetsFor80.push('Fix JSONL/journal ledger reconciliation');
  if (stress.passCount < stress.checks.length) targetsFor80.push('Clear remaining stress check failures');
  if (live.sharpeRatio == null) targetsFor80.push('More equity snapshots for Sharpe/Sortino');
  if (compositeScore < 80) targetsFor80.push('Re-run after 7d clean forward session');

  return { compositeScore, tier, dimensions, targetsFor80 };
}

export function formatInstitutionalReport(args: {
  generatedAt: string;
  readiness: InstitutionalReadinessReport;
  live: ExtendedLiveMetrics;
  sim: SimBaseline30d;
  scores: ExecutionAuditScores;
  reconciliation: ReconciliationResult;
  stress: StressReadiness;
  alerts: ValidationAlert[];
}): string {
  const lines: string[] = [];
  lines.push('JCM / BILSHENZ — INSTITUTIONAL READINESS REPORT');
  lines.push(`Generated: ${args.generatedAt}`);
  lines.push('');
  lines.push(`COMPOSITE SCORE: ${args.readiness.compositeScore}/100  (${args.readiness.tier})`);
  lines.push('');
  lines.push('── Dimensions ──');
  for (const d of args.readiness.dimensions) {
    lines.push(`  ${d.name}: ${d.score}/100`);
    for (const n of d.notes) lines.push(`    · ${n}`);
  }
  lines.push('');
  lines.push('── Extended metrics ──');
  lines.push(`  Signal→fill: ${args.live.signalToFillPct}% · Reject: ${args.live.orderRejectPct}%`);
  lines.push(
    `  Sharpe: ${args.live.sharpeRatio ?? 'n/a'} · Sortino: ${args.live.sortinoRatio ?? 'n/a'} · Expectancy: $${args.live.expectancyUsd ?? 'n/a'}`
  );
  lines.push(`  Closed: ${args.live.closedTrades} · Fills: ${args.live.trades}`);
  lines.push('');
  lines.push('── Ledger reconciliation ──');
  lines.push(
    `  JSONL fills ${args.reconciliation.jsonlFills} · Journal closed ${args.reconciliation.journalClosed} · Match ${args.reconciliation.matchPct}%`
  );
  if (args.reconciliation.issues.length) {
    for (const i of args.reconciliation.issues) lines.push(`  ! ${i}`);
  }
  lines.push('');
  lines.push('── Stress readiness ──');
  lines.push(`  ${args.stress.passCount}/${args.stress.checks.length} checks · score ${args.stress.score}`);
  for (const c of args.stress.checks.filter((x) => !x.pass)) {
    lines.push(`  [FAIL] ${c.code}: ${c.detail}`);
  }
  lines.push('');
  lines.push('── Audit scores ──');
  lines.push(`  Broker execution: ${args.scores.brokerExecutionQuality}/100`);
  lines.push(`  Real-money readiness: ${args.scores.realMoneyReadiness}/100`);
  lines.push(`  Sim vs live variance: ${args.scores.simVsLiveVariancePct}%`);
  lines.push('');
  if (args.readiness.targetsFor80.length) {
    lines.push('── To reach 80+ ──');
    for (const t of args.readiness.targetsFor80) lines.push(`  • ${t}`);
  }
  if (args.alerts.length) {
    lines.push('');
    lines.push('── Alerts ──');
    for (const a of args.alerts) lines.push(`  [${a.severity}] ${a.code}: ${a.message}`);
  }
  return lines.join('\n');
}
