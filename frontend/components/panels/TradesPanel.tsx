"use client";

import { useEffect, useState } from "react";
import { Panel } from "@/components/Panel";
import { endpoints, fetchApi } from "@/lib/api";

interface Trade {
  id: string;
  event_id: string;
  symbol: string;
  direction: string | null;
  outcome: string;
  pnl_usd: number | null;
  market_regime: string;
  trading_session: string;
  bsv32_confidence: number | null;
  created_at: string;
}

export function TradesPanel() {
  const [trades, setTrades] = useState<Trade[]>([]);

  useEffect(() => {
    const load = () => fetchApi<Trade[]>(endpoints.trades + "?limit=30").then(setTrades).catch(() => {});
    load();
    const i = setInterval(load, 20000);
    return () => clearInterval(i);
  }, []);

  return (
    <Panel title="Active & Recent Trades">
      {trades.length === 0 ? (
        <p className="text-terminal-muted text-sm">No trade events recorded yet.</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm font-mono">
            <thead>
              <tr className="text-terminal-muted text-left border-b border-terminal-border">
                <th className="pb-2 pr-4">Time</th>
                <th className="pb-2 pr-4">Symbol</th>
                <th className="pb-2 pr-4">Dir</th>
                <th className="pb-2 pr-4">Outcome</th>
                <th className="pb-2 pr-4">P&L</th>
                <th className="pb-2 pr-4">Regime</th>
                <th className="pb-2">Conf</th>
              </tr>
            </thead>
            <tbody>
              {trades.map((t) => (
                <tr key={t.id} className="border-b border-terminal-border/50">
                  <td className="py-2 pr-4 text-terminal-muted">
                    {new Date(t.created_at).toLocaleString()}
                  </td>
                  <td className="py-2 pr-4">{t.symbol}</td>
                  <td className="py-2 pr-4">{t.direction || "—"}</td>
                  <td className={`py-2 pr-4 ${t.outcome === "win" ? "text-terminal-green" : t.outcome === "loss" ? "text-terminal-red" : ""}`}>
                    {t.outcome}
                  </td>
                  <td className="py-2 pr-4">{t.pnl_usd != null ? `$${Number(t.pnl_usd).toFixed(2)}` : "—"}</td>
                  <td className="py-2 pr-4">{t.market_regime}</td>
                  <td className="py-2">{t.bsv32_confidence != null ? Number(t.bsv32_confidence).toFixed(2) : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  );
}
