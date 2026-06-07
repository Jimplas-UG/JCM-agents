/**
 * Production watchdog — polls services, auto-restarts on failure, resets bot failsafe.
 * Runs via Bilshenz-Watchdog scheduled task.
 */
import * as fs from 'node:fs';
import * as path from 'node:path';
import { execSync } from 'node:child_process';

const DESK = process.env.DESK_HEALTH_URL ?? 'http://127.0.0.1:8791/health';
const MT5 = (process.env.MT5_API_URL ?? 'http://127.0.0.1:8765').replace(/\/$/, '');
const INTERVAL_MS = Number(process.env.WATCHDOG_INTERVAL_MS ?? 60_000);
const LOG_DIR = process.env.TRADINGBOT_LOG_DIR ?? 'C:\\logs\\tradingbot';
const SAFETY_FILE = process.env.SAFETY_STATE_PATH ?? path.join(LOG_DIR, 'safety-state.json');
const SYMBOL = process.env.MT5_SYMBOL ?? 'XAUUSD';
/** Tick older than this → treat feed as stale (silent disconnect). */
const MAX_TICK_AGE_SEC = Number(process.env.WATCHDOG_MAX_TICK_AGE_SEC ?? 180);

const MT5_TERMINAL_PATH = process.env.MT5_TERMINAL_PATH ?? 'C:\\Program Files\\MetaTrader 5 Exness';

let prevDesk = true;
let prevMt5 = true;
let deskDownCount = 0;
let mt5DownCount = 0;
let staleTickCount = 0;
let forwardMissingCount = 0;
let lastForwardRestartMs = 0;
const RESTART_AFTER = 3;
const FORWARD_RESTART_COOLDOWN_MS = 600_000; // 10 min — avoid restart thrashing

function log(msg: string): void {
  const ts = new Date().toISOString();
  const line = `${ts} [watchdog] ${msg}`;
  console.log(line);
  try {
    fs.appendFileSync(path.join(LOG_DIR, 'watchdog.log'), line + '\n', 'utf8');
  } catch { /* ignore */ }
}

function logReconnect(message: string, extra: Record<string, unknown> = {}): void {
  if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
  const line =
    JSON.stringify({ ts: new Date().toISOString(), event: 'reconnect', message, ...extra }) + '\n';
  fs.appendFileSync(path.join(LOG_DIR, 'reconnect.jsonl'), line, 'utf8');
}

function runPs(cmd: string, timeoutMs = 90_000): string {
  try {
    return execSync(`powershell -NoProfile -Command "${cmd}"`, { timeout: timeoutMs, encoding: 'utf8' }).trim();
  } catch (e) {
    return e instanceof Error ? e.message : String(e);
  }
}

async function probeTickAge(): Promise<{ ok: boolean; ageSec: number; detail: string }> {
  try {
    const res = await fetch(`${MT5}/api/tick/${encodeURIComponent(SYMBOL)}`, {
      signal: AbortSignal.timeout(10_000),
    });
    if (!res.ok) return { ok: false, ageSec: 9999, detail: `tick HTTP ${res.status}` };
    const j = (await res.json()) as { time?: number };
    const tickSec = Number(j.time);
    if (!Number.isFinite(tickSec) || tickSec <= 0) {
      return { ok: false, ageSec: 9999, detail: 'tick time missing' };
    }
    const ageSec = Math.max(0, Math.floor(Date.now() / 1000 - tickSec));
    return {
      ok: ageSec <= MAX_TICK_AGE_SEC,
      ageSec,
      detail: `tick_age_sec=${ageSec}`,
    };
  } catch (e) {
    return {
      ok: false,
      ageSec: 9999,
      detail: e instanceof Error ? e.message : String(e),
    };
  }
}

async function probe(url: string): Promise<{ ok: boolean; detail: string }> {
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(10_000) });
    const text = await res.text();
    let ok = res.ok;
    if (url.includes('/api/status') && res.ok) {
      try {
        const j = JSON.parse(text) as {
          connected?: boolean;
          terminal_trade_allowed?: boolean;
          trade_allowed?: boolean;
          account?: { trade_allowed?: boolean };
        };
        const connected = Boolean(j.connected);
        const terminalTrade = !!j.terminal_trade_allowed;
        const accountTrade = !!(j.trade_allowed ?? j.account?.trade_allowed);
        ok = connected && terminalTrade && accountTrade;
        if (connected && !terminalTrade) {
          return {
            ok: false,
            detail: 'connected but AutoTrading disabled (retcode 10027 risk)',
          };
        }
      } catch { ok = false; }
    }
    return { ok, detail: text.slice(0, 200) };
  } catch (e) {
    return { ok: false, detail: e instanceof Error ? e.message : String(e) };
  }
}

/** Restart MT5 terminal when algo trading is off but process is running. */
function ensureAlgoTradingEnabled(): void {
  try {
    const result = runPs("(Get-Process terminal64 -ErrorAction SilentlyContinue).Id");
    if (!result?.match(/\d+/)) return;
    const detail = runPs(
      `(Invoke-RestMethod '${MT5}/api/status' -TimeoutSec 8).terminal_trade_allowed`
    );
    if (detail.toLowerCase() === 'true') return;
    log('AutoTrading disabled — restarting terminal64 with /algotrading');
    runPs('taskkill /f /im terminal64.exe 2>$null');
    runPs('Start-Sleep 8');
    const exe = `${MT5_TERMINAL_PATH}\\terminal64.exe`;
    runPs(`Start-Process '${exe}' -ArgumentList '/algotrading'`);
    runPs('Start-Sleep 45');
    logReconnect('terminal64 restarted for AutoTrading', { service: 'terminal64', reason: 'algo_trading_off' });
  } catch (e) {
    log(`ensureAlgoTrading error: ${e instanceof Error ? e.message : String(e)}`);
  }
}

function ensureTerminal64(): void {
  try {
    const result = runPs("(Get-Process terminal64 -ErrorAction SilentlyContinue).Id");
    if (result && result.match(/\d+/)) return;
    const exe = `${MT5_TERMINAL_PATH}\\terminal64.exe`;
    const check = runPs(`Test-Path '${exe}'`);
    if (check.toLowerCase() !== 'true') {
      log(`terminal64.exe not found at ${exe}`);
      return;
    }
    log('terminal64 not running — starting with /algotrading...');
    runPs(`Start-Process '${exe}' -ArgumentList '/algotrading'`);
    logReconnect('terminal64 started by watchdog', { service: 'terminal64' });
  } catch (e) {
    log(`ensureTerminal64 error: ${e instanceof Error ? e.message : String(e)}`);
  }
}

function resetBotFailsafe(): void {
  try {
    if (!fs.existsSync(SAFETY_FILE)) return;
    const state = JSON.parse(fs.readFileSync(SAFETY_FILE, 'utf8'));
    if (state.failsafe || state.consecutiveApiFailures >= 6) {
      state.consecutiveApiFailures = 0;
      state.failsafe = false;
      state.failsafeReason = null;
      fs.writeFileSync(SAFETY_FILE, JSON.stringify(state, null, 2), 'utf8');
      log('Reset bot failsafe — MT5 is healthy again');
    }
  } catch { /* ignore */ }
}

function forwardLogFresh(): boolean {
  try {
    for (const name of ['forward-bot.err.log', 'forward-bot.log']) {
      const p = path.join(LOG_DIR, name);
      if (fs.existsSync(p) && fs.statSync(p).size > 0) {
        if (Date.now() - fs.statSync(p).mtimeMs < 120_000) return true;
      }
    }
  } catch { /* ignore */ }
  return false;
}

function restartMt5FullStack(reason: string): void {
  log(`Full MT5 restart: ${reason}`);
  runPs(
    "Get-Process python -ErrorAction SilentlyContinue | Where-Object { $_.Path -match 'bilshenz|mt5_trading_system' } | Stop-Process -Force -ErrorAction SilentlyContinue"
  );
  runPs('taskkill /f /im terminal64.exe 2>$null');
  runPs('Start-Sleep 10');
  const exe = `${MT5_TERMINAL_PATH}\\terminal64.exe`;
  runPs(`Start-Process '${exe}' -ArgumentList '/algotrading'`);
  runPs('Start-Sleep 60');
  runPs("Start-ScheduledTask -TaskName 'Bilshenz-MT5-API'");
  runPs('Start-Sleep 15');
  logReconnect('full MT5 stack restarted by watchdog', { service: 'mt5-full', reason });
  mt5DownCount = 0;
  staleTickCount = 0;
}

async function tick(): Promise<void> {
  ensureTerminal64();
  ensureAlgoTradingEnabled();

  const desk = await probe(DESK);
  const mt5 = await probe(`${MT5}/api/status`);
  const tick = mt5.ok ? await probeTickAge() : { ok: false, ageSec: 9999, detail: 'mt5 down' };
  const mt5Healthy = mt5.ok && tick.ok;

  if (!desk.ok) {
    deskDownCount++;
    if (prevDesk) {
      logReconnect('desk-api down', { service: 'desk-api' });
      log(`desk-api DOWN: ${desk.detail}`);
    }
    if (deskDownCount >= RESTART_AFTER) {
      log('Restarting Bilshenz-DeskAPI...');
      runPs("Get-NetTCPConnection -LocalPort 8791 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }; Start-Sleep 3; Start-ScheduledTask -TaskName 'Bilshenz-DeskAPI'");
      deskDownCount = 0;
    }
  } else {
    if (!prevDesk) {
      logReconnect('desk-api recovered', { service: 'desk-api' });
      log('desk-api recovered');
    }
    deskDownCount = 0;
  }

  if (!mt5Healthy) {
    if (!mt5.ok) {
      mt5DownCount++;
      staleTickCount = 0;
      if (prevMt5) {
        logReconnect('mt5-api disconnected', { service: 'mt5-api', detail: mt5.detail });
        log(`MT5 DOWN: ${mt5.detail}`);
      }
      if (mt5DownCount >= RESTART_AFTER) {
        restartMt5FullStack('mt5-api down for 3 checks');
      }
    } else {
      mt5DownCount = 0;
      // Weekend/holiday: tick frozen for hours — do not restart MT5 stack
      if (tick.ageSec > 7200) {
        if (staleTickCount > 0) {
          log(`Market-closed tick age ${tick.ageSec}s — skipping stale restart`);
        }
        staleTickCount = 0;
      } else {
        staleTickCount++;
        if (prevMt5 && staleTickCount === 1) {
          logReconnect('mt5 tick feed stale', {
            service: 'mt5-tick',
            tick_age_sec: tick.ageSec,
            symbol: SYMBOL,
          });
          log(`MT5 tick STALE (${tick.ageSec}s): ${tick.detail}`);
        }
        if (staleTickCount >= RESTART_AFTER) {
          restartMt5FullStack(`stale tick feed ${tick.ageSec}s for ${RESTART_AFTER} checks`);
        }
      }
    }
  } else {
    if (!prevMt5) {
      logReconnect('mt5-api connected', { service: 'mt5-api' });
      log('MT5 recovered');
      resetBotFailsafe();
    }
    mt5DownCount = 0;
    staleTickCount = 0;
    resetBotFailsafe();
  }

  if (desk.ok && mt5Healthy) {
    try {
      if (fs.existsSync(SAFETY_FILE)) {
        const state = JSON.parse(fs.readFileSync(SAFETY_FILE, 'utf8'));
        if (state.failsafe || state.consecutiveApiFailures > 0) {
          state.consecutiveApiFailures = 0;
          state.failsafe = false;
          state.failsafeReason = null;
          fs.writeFileSync(SAFETY_FILE, JSON.stringify(state, null, 2), 'utf8');
          log('Cleared bot failsafe + API failure counter — both services healthy');
        }
      }
    } catch { /* ignore */ }
  }

  // Ensure exactly one forward bot worker (stable detection — do not thrash restarts)
  try {
    const botPids = runPs(
      "$p = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | " +
      "Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -match 'loader\\.mjs.*run-forward-demo-30d' }; " +
      "if ($p) { ($p | Select-Object -ExpandProperty ProcessId) -join ',' }"
    );
    const ids = (botPids.match(/\d+/g) ?? []).map((x) => parseInt(x, 10)).filter((x) => x > 0);
    const logFresh = forwardLogFresh();
    if (ids.length === 0 && !logFresh) {
      forwardMissingCount++;
      const taskState = runPs(
        "$t = Get-ScheduledTask -TaskName 'Bilshenz-ForwardBot-Sys' -ErrorAction SilentlyContinue; " +
        "if (-not $t) { $t = Get-ScheduledTask -TaskName 'Bilshenz-ForwardBot' -ErrorAction SilentlyContinue }; " +
        "if ($t) { $t.State } else { 'Missing' }"
      );
      let logStale = true;
      try {
        const logNames = ['forward-bot.err.log', 'forward-bot.out.log', 'forward-bot.log'];
        let newest = 0;
        for (const name of logNames) {
          const logPath = path.join(LOG_DIR, name);
          if (fs.existsSync(logPath) && fs.statSync(logPath).size > 0) {
            newest = Math.max(newest, fs.statSync(logPath).mtimeMs);
          }
        }
        if (newest > 0) logStale = Date.now() - newest > 180_000;
      } catch { /* ignore */ }
      const cooldownOk = Date.now() - lastForwardRestartMs > FORWARD_RESTART_COOLDOWN_MS;
      if (
        taskState !== 'Running' &&
        forwardMissingCount >= RESTART_AFTER &&
        logStale &&
        cooldownOk
      ) {
        log('Forward bot missing — starting Bilshenz-ForwardBot-Sys (after 3 checks + stale log)');
        runPs(
          "Start-ScheduledTask -TaskName 'Bilshenz-ForwardBot-Sys' -ErrorAction SilentlyContinue; " +
          "if (-not $?) { Start-ScheduledTask -TaskName 'Bilshenz-ForwardBot' -ErrorAction SilentlyContinue }; " +
          "Start-Sleep 15; " +
          "$alive = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | " +
          "Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d' }; " +
          "if (-not $alive) { " +
          "& 'C:\\opt\\bilshenz\\deploy\\windows\\run-forward-bot.ps1' -AppDir 'C:\\opt\\bilshenz' " +
          "}"
        );
        logReconnect('forward bot started by watchdog', { service: 'forward-bot' });
        lastForwardRestartMs = Date.now();
        forwardMissingCount = 0;
      }
    } else {
      forwardMissingCount = 0;
    }
  } catch { /* ignore */ }

  const ts = new Date().toISOString().slice(11, 19);
  const tickNote = mt5.ok && !tick.ok ? ` tick_age=${tick.ageSec}s` : '';
  const heartbeat = `${ts} desk=${desk.ok} mt5=${mt5Healthy}${!mt5Healthy ? ' ' + (mt5.detail || tick.detail).slice(0, 80) : ''}${tickNote}`;
  console.log(heartbeat);
  log(heartbeat);

  prevDesk = desk.ok;
  prevMt5 = mt5Healthy;
}

async function main(): Promise<void> {
  if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
  log(`Started — desk=${DESK} mt5=${MT5}/api/status interval=${INTERVAL_MS}ms`);
  await tick();
  setInterval(() => void tick(), INTERVAL_MS);
}

void main();
