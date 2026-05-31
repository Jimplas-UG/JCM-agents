/**
 * Observability-only: detect MT5 position closes and publish trade_closed to JCM.
 * Does not modify BSv3.2 strategy or order logic.
 */

import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

import { jcmWebhookConfigured, publishTradeClosed } from './jcmSupervisorPublisher';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_ROOT = path.join(__dirname, '..');
const STATE_FILE = path.join(BACKEND_ROOT, 'validation', 'data', 'jcm-position-watch.json');

const MT5_API = (process.env.MT5_API_URL ?? 'http://127.0.0.1:8765').replace(/\/$/, '');

type TrackedPosition = {
  ticket: number;
  symbol: string;
  direction: 'long' | 'short';
  lotSize: number;
  entryPrice: number;
  lastProfit: number;
  lastPrice: number;
  seenAtMs: number;
};

type WatchState = {
  positions: Record<string, TrackedPosition>;
};

function loadState(): WatchState {
  if (!fs.existsSync(STATE_FILE)) return { positions: {} };
  try {
    const raw = fs.readFileSync(STATE_FILE, 'utf8').replace(/^\uFEFF/, '');
    const j = JSON.parse(raw) as WatchState;
    return { positions: j.positions ?? {} };
  } catch {
    return { positions: {} };
  }
}

function saveState(state: WatchState): void {
  const dir = path.dirname(STATE_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
}

function outcomeFromPnl(pnl: number): 'win' | 'loss' | 'breakeven' {
  if (pnl > 0.01) return 'win';
  if (pnl < -0.01) return 'loss';
  return 'breakeven';
}

type Mt5Position = {
  ticket?: number;
  symbol?: string;
  type?: number | string;
  volume?: number;
  price_open?: number;
  price_current?: number;
  profit?: number;
};

async function fetchMt5Positions(): Promise<Mt5Position[]> {
  const res = await fetch(`${MT5_API}/api/positions`);
  if (!res.ok) return [];
  const j = (await res.json()) as { positions?: Mt5Position[] };
  return j.positions ?? [];
}

function normalizeDirection(p: Mt5Position): 'long' | 'short' {
  const t = p.type;
  if (t === 0 || t === 'buy' || t === 'BUY' || t === 'long') return 'long';
  return 'short';
}

/** Poll MT5 open positions; emit trade_closed when a tracked ticket disappears. */
export async function pollJcmPositionCloses(): Promise<number> {
  if (!jcmWebhookConfigured()) return 0;

  const state = loadState();
  const prevKeys = new Set(Object.keys(state.positions));
  const current: Record<string, TrackedPosition> = {};
  let closedCount = 0;

  try {
    const rows = await fetchMt5Positions();
    for (const p of rows) {
      const ticket = Number(p.ticket);
      if (!Number.isFinite(ticket)) continue;
      const key = String(ticket);
      const existing = state.positions[key];
      current[key] = {
        ticket,
        symbol: String(p.symbol ?? 'XAUUSD'),
        direction: normalizeDirection(p),
        lotSize: Number(p.volume ?? existing?.lotSize ?? 0.01),
        entryPrice: Number(p.price_open ?? existing?.entryPrice ?? 0),
        lastProfit: Number(p.profit ?? existing?.lastProfit ?? 0),
        lastPrice: Number(p.price_current ?? existing?.lastPrice ?? p.price_open ?? 0),
        seenAtMs: Date.now(),
      };
      prevKeys.delete(key);
    }

    for (const key of prevKeys) {
      const gone = state.positions[key];
      if (!gone) continue;
      const pnl = gone.lastProfit;
      const ok = await publishTradeClosed({
        symbol: gone.symbol,
        direction: gone.direction,
        lotSize: gone.lotSize,
        entryPrice: gone.entryPrice,
        exitPrice: gone.lastPrice,
        pnlUsd: pnl,
        outcome: outcomeFromPnl(pnl),
        mt5Ticket: gone.ticket,
        closedAtMs: Date.now(),
      });
      if (ok) {
        closedCount += 1;
        console.error(
          `[jcm] trade_closed ${gone.symbol} ${gone.direction} ticket=${gone.ticket} pnl=$${pnl.toFixed(2)}`
        );
      }
    }

    saveState({ positions: current });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[jcm] position watch failed: ${msg}`);
  }

  return closedCount;
}
