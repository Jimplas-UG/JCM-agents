/**
 * Allocator due-diligence gates — stricter than institutional readiness.
 * A "check" requires ALL hard gates (50+ live closes, 90d track, 90% fill, etc.).
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { DEFAULT_ALERT_THRESHOLDS, evaluateValidationAlerts } from './validation/alerts';
import { computeDrift, liveStatsFromEvents, simVsLiveVariancePct } from './validation/driftAnalysis';
import { buildExecutionAuditScores } from './validation/executionAuditReport';
import { extendLiveMetrics } from './validation/institutionalMetrics';
import {
  buildTcaSummary,
  computeAllocatorReadiness,
  formatAllocatorReport,
  loadResearchAttestation,
} from './validation/allocatorGates';
import { evaluateStressReadiness } from './validation/stressChecks';
import { reconcileForwardLedger } from './validation/tradeReconciliation';
import { filterEvents, forwardDemoLogPath, loadForwardDemoEvents } from './validation/forwardDemoStore';
import { productionFrozenConfig, verifyFrozenStrategy } from '../strategy/frozenProduction';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_ROOT = path.join(__dirname, '..');
const DATA_DIR = path.join(BACKEND_ROOT, 'validation', 'data');
const REPORT_PATH = path.join(DATA_DIR, 'allocator-readiness-report.txt');
const JSON_PATH = path.join(DATA_DIR, 'allocator-readiness.json');

function loadJournal(): Array<Record<string, unknown>> {
  const p = path.join(DATA_DIR, 'forward-demo-journal.json');
  if (!fs.existsSync(p)) return [];
  try {
    const j = JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')) as { rows?: unknown[] };
    return (j.rows ?? []) as Array<Record<string, unknown>>;
  } catch {
    return [];
  }
}

function loadSessionDays(): number {
  const p = path.join(DATA_DIR, 'forward-demo-session.json');
  if (!fs.existsSync(p)) return 0;
  try {
    const s = JSON.parse(fs.readFileSync(p, 'utf8')) as { startMs?: number };
    if (!s.startMs) return 0;
    return Math.max(0, Math.floor((Date.now() - s.startMs) / 86400000));
  } catch {
    return 0;
  }
}

function loadSimBaseline(): import('./validation/types').SimBaseline30d {
  const candidates = [
    path.join(BACKEND_ROOT, 'scripts', 'forward-sim-baseline-30d.json'),
    path.join(DATA_DIR, 'forward-sim-baseline-30d.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return JSON.parse(fs.readFileSync(p, 'utf8'));
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

async function probeInfra() {
  let mt5Connected = false;
  let autoTrading = false;
  let failsafeActive = false;
  let forwardProcessUp = false;
  let jcmIngestOk = false;
  try {
    const r = await fetch('http://127.0.0.1:8765/api/status', { signal: AbortSignal.timeout(8000) });
    if (r.ok) {
      const j = (await r.json()) as { connected?: boolean; terminal_trade_allowed?: boolean };
      mt5Connected = !!j.connected;
      autoTrading = !!j.terminal_trade_allowed;
    }
  } catch {
    /* down */
  }
  const safetyPath =
    process.platform === 'win32' ? 'C:\\logs\\tradingbot\\safety-state.json' : '/var/log/tradingbot/safety-state.json';
  if (fs.existsSync(safetyPath)) {
    try {
      failsafeActive = !!(JSON.parse(fs.readFileSync(safetyPath, 'utf8')) as { failsafe?: boolean }).failsafe;
    } catch {
      /* ignore */
    }
  }
  const errLog =
    process.platform === 'win32' ? 'C:\\logs\\tradingbot\\forward-bot.err.log' : '/var/log/tradingbot/forward-bot.err.log';
  if (fs.existsSync(errLog) && Date.now() - fs.statSync(errLog).mtimeMs < 300_000) {
    forwardProcessUp = true;
  }
  try {
    jcmIngestOk = (await fetch('http://127.0.0.1:8000/health', { signal: AbortSignal.timeout(6000) })).ok;
  } catch {
    jcmIngestOk = false;
  }
  return { mt5Connected, autoTrading, failsafeActive, forwardProcessUp, jcmIngestOk };
}

async function fetchStaleJcmOpens(): Promise<number> {
  try {
    const r = await fetch('http://127.0.0.1:8000/dashboard/allocator-readiness', {
      signal: AbortSignal.timeout(8000),
      headers: { 'X-API-Key': process.env.JCM_API_KEY ?? '' },
    });
    if (!r.ok) return -1;
    const j = (await r.json()) as { stale_jcm_opens?: number };
    return j.stale_jcm_opens ?? -1;
  } catch {
    return -1;
  }
}

async function main() {
  const sinceMs = Date.now() - 30 * 86400000;
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
  const recentEvents = filterEvents(events, { sinceMs: Date.now() - 2 * 86400000 });
  const recentLive = extendLiveMetrics(
    liveStatsFromEvents(recentEvents, sim.startEquity, BACKEND_ROOT),
    recentEvents,
    journal as never[]
  );
  const recentReject =
    recentLive.orderIntents + recentLive.trades > 0 ? recentLive.orderRejectPct : 0;
  const stress = evaluateStressReadiness(live, sim, infra, recentReject);
  const research = loadResearchAttestation([
    path.join(DATA_DIR, 'backtest-xau-12mo-live-realistic-mt5-output.txt'),
    ...fs
      .readdirSync(DATA_DIR)
      .filter((f) => f.includes('realistic-mt5') && f.endsWith('-output.txt'))
      .map((f) => path.join(DATA_DIR, f)),
  ]);
  const tca = buildTcaSummary(live, sim, recentReject);
  const liveDays = loadSessionDays();
  let staleJcmOpens = await fetchStaleJcmOpens();
  const stateFile = path.join(DATA_DIR, 'allocator-pipeline-state.json');
  if (fs.existsSync(stateFile)) {
    try {
      const st = JSON.parse(fs.readFileSync(stateFile, 'utf8')) as { stale_jcm_opens?: number };
      if (typeof st.stale_jcm_opens === 'number') staleJcmOpens = st.stale_jcm_opens;
    } catch {
      /* ignore */
    }
  }
  if (staleJcmOpens < 0) staleJcmOpens = 0;

  const haltFlag = path.join(
    process.platform === 'win32' ? 'C:\\logs\\tradingbot' : '/var/log/tradingbot',
    'allocator-halt.json'
  );
  const killSwitchEnforced = fs.existsSync(haltFlag) || process.env.KILL_SWITCH_ENFORCED === '1';

  const report = computeAllocatorReadiness({
    live,
    sim,
    reconciliation,
    stress,
    research,
    tca,
    liveDays,
    staleJcmOpens,
    killSwitchEnforced,
  });

  const text = formatAllocatorReport({
    generatedAt: new Date().toISOString(),
    report,
    research,
    tca,
  });

  if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.writeFileSync(REPORT_PATH, text, 'utf8');
  fs.writeFileSync(
    JSON_PATH,
    JSON.stringify({ report, research, tca, live, scores, freezeOk: freeze.ok, liveDays }, null, 2),
    'utf8'
  );

  console.log(text);
  console.error(`\nReport: ${REPORT_PATH}`);
  process.exit(report.checkReady ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
