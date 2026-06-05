import type { ExtendedLiveMetrics } from './institutionalMetrics';
import type { SimBaseline30d, ValidationAlert } from './types';

export type StressCheck = {
  code: string;
  pass: boolean;
  detail: string;
};

export type StressReadiness = {
  checks: StressCheck[];
  passCount: number;
  score: number;
};

/** Operational stress readiness (infra reactions — not Monte Carlo). */
export function evaluateStressReadiness(
  live: ExtendedLiveMetrics,
  sim: SimBaseline30d,
  infra: {
    mt5Connected: boolean;
    autoTrading: boolean;
    failsafeActive: boolean;
    forwardProcessUp: boolean;
    jcmIngestOk: boolean;
  },
  recentRejectPct?: number
): StressReadiness {
  const rejectPct = recentRejectPct ?? live.orderRejectPct;
  const checks: StressCheck[] = [
    {
      code: 'SPREAD_EXPANSION',
      pass: live.avgSpreadPips <= sim.spreadPips * 2.5,
      detail: `avg spread ${live.avgSpreadPips.toFixed(2)}p vs sim ${sim.spreadPips}p`,
    },
    {
      code: 'LATENCY_SPIKE',
      pass: live.avgLatencyMs <= 2500,
      detail: `avg latency ${live.avgLatencyMs.toFixed(0)}ms`,
    },
    {
      code: 'API_OUTAGE_RECOVERY',
      pass: !infra.failsafeActive,
      detail: infra.failsafeActive ? 'failsafe active' : 'failsafe clear',
    },
    {
      code: 'MT5_UPTIME',
      pass: infra.mt5Connected && infra.autoTrading,
      detail: `connected=${infra.mt5Connected} autotrading=${infra.autoTrading}`,
    },
    {
      code: 'FORWARD_WORKER',
      pass: infra.forwardProcessUp,
      detail: infra.forwardProcessUp ? 'forward bot running' : 'forward bot down',
    },
    {
      code: 'JCM_INGEST',
      pass: infra.jcmIngestOk,
      detail: infra.jcmIngestOk ? 'ingest probe OK' : 'ingest failed recently',
    },
    {
      code: 'REJECT_STORM',
      pass: rejectPct < 25,
      detail: `reject rate ${rejectPct.toFixed(1)}% (recent window)`,
    },
    {
      code: 'DRAWDOWN_BUFFER',
      pass: live.maxDrawdownUsd <= Math.max(400, sim.maxDrawdownUsd * 1.5),
      detail: `DD $${live.maxDrawdownUsd.toFixed(0)} vs sim $${sim.maxDrawdownUsd.toFixed(0)}`,
    },
  ];

  const passCount = checks.filter((c) => c.pass).length;
  const score = Math.round((passCount / checks.length) * 100);
  return { checks, passCount, score };
}

export function stressAlerts(readiness: StressReadiness): ValidationAlert[] {
  return readiness.checks
    .filter((c) => !c.pass)
    .map((c) => ({
      code: `STRESS_${c.code}`,
      severity: 'WARN' as const,
      message: `Stress check failed: ${c.code} — ${c.detail}`,
    }));
}
