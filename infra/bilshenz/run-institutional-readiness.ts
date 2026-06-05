/**
 * Institutional readiness report — composite 80+ target (observability + ops).
 * Usage: npx tsx scripts/run-institutional-readiness.ts [--days=30] [--infra-score=68]
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { DEFAULT_ALERT_THRESHOLDS, evaluateValidationAlerts } from './validation/alerts';
import { computeDrift, liveStatsFromEvents, simVsLiveVariancePct } from './validation/driftAnalysis';
import { buildExecutionAuditScores } from './validation/executionAuditReport';
import { extendLiveMetrics } from './validation/institutionalMetrics';
import {
  computeInstitutionalReadiness,
  formatInstitutionalReport,
} from './validation/institutionalReadiness';
import { evaluateStressReadiness, stressAlerts } from './validation/stressChecks';
import { reconcileForwardLedger } from './validation/tradeReconciliation';
import { filterEvents, forwardDemoLogPath, loadForwardDemoEvents } from './validation/forwardDemoStore';
import { productionFrozenConfig, verifyFrozenStrategy } from '../strategy/frozenProduction';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_ROOT = path.join(__dirname, '..');
const REPORT_PATH = path.join(BACKEND_ROOT, 'validation', 'data', 'institutional-readiness-report.txt');
const JSON_PATH = path.join(BACKEND_ROOT, 'validation', 'data', 'institutional-readiness.json');
const BASELINE_CACHE = path.join(__dirname, 'forward-sim-baseline-30d.json');

function readDays(): number {
  const a = process.argv.find((x) => x.startsWith('--days='));
  return a ? Math.max(7, Math.min(90, parseInt(a.split('=')[1]!, 10))) : 30;
}

function readInfraScore(): number {
  const env = process.env.INST_INFRA_SCORE;
  if (env) {
    const n = parseInt(env, 10);
    if (Number.isFinite(n)) return Math.max(0, Math.min(100, n));
  }
  const a = process.argv.find((x) => x.startsWith('--infra-score='));
  return a ? Math.max(0, Math.min(100, parseInt(a.split('=')[1]!, 10))) : 68;
}

function loadJournal(): Array<Record<string, unknown>> {
  const p = path.join(BACKEND_ROOT, 'validation', 'data', 'forward-demo-journal.json');
  if (!fs.existsSync(p)) return [];
  try {
    const j = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')) as { rows?: unknown[] };
    return (j.rows ?? []) as Array<Record<string, unknown>>;
  } catch {
    return [];
  }
}

function loadSimBaseline(): import('./validation/types').SimBaseline30d {
  if (fs.existsSync(BASELINE_CACHE)) {
    return JSON.parse(fs.readFileSync(BASELINE_CACHE, 'utf8'));
  }
  return {
    windowDays: 30,
    generatedAt: new Date().toISOString(),
    startEquity: 1000,
    endEquity: 1000,
    netPct: 0,
    trades: 46,
    winRatePct: 63,
    profitFactor: 3.03,
    maxDrawdownUsd: 1652,
    spreadPips: 3.08,
    slippagePipsPerSide: 0.4,
  };
}

async function probeInfra(): Promise<{
  mt5Connected: boolean;
  autoTrading: boolean;
  failsafeActive: boolean;
  forwardProcessUp: boolean;
  jcmIngestOk: boolean;
}> {
  let mt5Connected = false;
  let autoTrading = false;
  try {
    const r = await fetch('http://127.0.0.1:8765/api/status', { signal: AbortSignal.timeout(8000) });
    if (r.ok) {
      const j = (await r.json()) as {
        connected?: boolean;
        terminal_trade_allowed?: boolean;
      };
      mt5Connected = !!j.connected;
      autoTrading = !!j.terminal_trade_allowed;
    }
  } catch {
    /* down */
  }

  let failsafeActive = false;
  const safetyPath =
    process.platform === 'win32' ? 'C:\\logs\\tradingbot\\safety-state.json' : '/var/log/tradingbot/safety-state.json';
  if (fs.existsSync(safetyPath)) {
    try {
      const s = JSON.parse(fs.readFileSync(safetyPath, 'utf8')) as { failsafe?: boolean };
      failsafeActive = !!s.failsafe;
    } catch {
      /* ignore */
    }
  }

  let forwardProcessUp = false;
  const errLog =
    process.platform === 'win32' ? 'C:\\logs\\tradingbot\\forward-bot.err.log' : '/var/log/tradingbot/forward-bot.err.log';
  if (fs.existsSync(errLog)) {
    const ageMs = Date.now() - fs.statSync(errLog).mtimeMs;
    if (ageMs < 300_000) forwardProcessUp = true;
  }
  if (!forwardProcessUp && process.platform === 'win32') {
    try {
      const { execSync } = await import('child_process');
      const out = execSync(
        'powershell -NoProfile -Command "(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -eq \'node.exe\' -and $_.CommandLine -match \'run-forward-demo\' }).Count"',
        { encoding: 'utf8', timeout: 8000 }
      ).trim();
      forwardProcessUp = parseInt(out, 10) > 0;
    } catch {
      forwardProcessUp = false;
    }
  }

  let jcmIngestOk = true;
  try {
    const h = await fetch('http://127.0.0.1:8000/health', { signal: AbortSignal.timeout(6000) });
    jcmIngestOk = h.ok;
  } catch {
    jcmIngestOk = false;
  }

  return { mt5Connected, autoTrading, failsafeActive, forwardProcessUp, jcmIngestOk };
}

async function main() {
  const days = readDays();
  const infraScore = readInfraScore();
  const sinceMs = Date.now() - days * 86400000;

  const freeze = verifyFrozenStrategy(BACKEND_ROOT, productionFrozenConfig());
  const sim = loadSimBaseline();
  const events = filterEvents(loadForwardDemoEvents(0), { sinceMs });
  const journal = loadJournal();
  const baseLive = liveStatsFromEvents(events, sim.startEquity, BACKEND_ROOT);
  const live = extendLiveMetrics(baseLive, events, journal as never[]);
  const drift = computeDrift(sim, live);
  const variancePct = simVsLiveVariancePct(drift, sim, live);
  const alerts = evaluateValidationAlerts(sim, live, drift, DEFAULT_ALERT_THRESHOLDS);
  const scores = buildExecutionAuditScores(variancePct, live, alerts);
  const reconciliation = reconcileForwardLedger(events, journal as never[]);
  const infra = await probeInfra();
  const recentSinceMs = Date.now() - 2 * 86400000;
  const recentEvents = filterEvents(events, { sinceMs: recentSinceMs });
  const recentBase = liveStatsFromEvents(recentEvents, sim.startEquity, BACKEND_ROOT);
  const recentLive = extendLiveMetrics(recentBase, recentEvents, journal as never[]);
  const recentRejectPct =
    recentLive.orderIntents + recentLive.trades > 0
      ? recentLive.orderRejectPct
      : 0;
  const stress = evaluateStressReadiness(live, sim, infra, recentRejectPct);
  alerts.push(...stressAlerts(stress));

  const readiness = computeInstitutionalReadiness({
    freezeOk: freeze.ok,
    live,
    sim,
    scores,
    reconciliation,
    stress,
    infraScore,
  });

  const report = formatInstitutionalReport({
    generatedAt: new Date().toISOString(),
    readiness,
    live,
    sim,
    scores,
    reconciliation,
    stress,
    alerts,
  });

  const dir = path.dirname(REPORT_PATH);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(REPORT_PATH, report, 'utf8');
  fs.writeFileSync(
    JSON_PATH,
    JSON.stringify({ readiness, live, scores, reconciliation, stress, freezeOk: freeze.ok }, null, 2),
    'utf8'
  );

  console.log(report);
  console.error(`\nReport: ${REPORT_PATH}`);
  console.error(`JSON: ${JSON_PATH}`);
  process.exit(readiness.compositeScore >= 80 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
