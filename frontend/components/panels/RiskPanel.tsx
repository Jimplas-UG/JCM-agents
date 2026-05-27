"use client";

import { useEffect, useState } from "react";
import { MetricCard } from "@/components/MetricCard";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { endpoints, fetchApi } from "@/lib/api";

interface RiskData {
  risk_score: number;
  account_drawdown_pct: number;
  daily_drawdown_pct: number;
  open_positions: number;
  lot_scaling_factor: number;
  kill_switch_recommended: boolean;
  correlated_pairs: { pair: string[]; correlation: number }[];
  alerts: { type: string; message: string; severity: string }[];
}

export function RiskPanel() {
  const [data, setData] = useState<RiskData | null>(null);

  useEffect(() => {
    const load = () => fetchApi<RiskData>(endpoints.risk).then(setData).catch(() => {});
    load();
    const i = setInterval(load, 30000);
    return () => clearInterval(i);
  }, []);

  if (!data) return <Panel title="Risk"><p className="text-terminal-muted text-sm">Loading...</p></Panel>;

  return (
    <div className="space-y-4">
      {data.kill_switch_recommended && (
        <div className="bg-terminal-red/10 border border-terminal-red rounded-lg p-4">
          <StatusBadge status="error" label="Kill-Switch Recommended" />
          <p className="text-sm mt-2 text-terminal-red">
            Human action required. Platform does not auto-disable BSv3.2.
          </p>
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <MetricCard label="Risk Score" value={(data.risk_score * 100).toFixed(1) + "%"} variant={data.risk_score > 0.7 ? "warning" : "default"} />
        <MetricCard label="Account DD" value={data.account_drawdown_pct.toFixed(2) + "%"} variant={data.account_drawdown_pct > 3 ? "negative" : "default"} />
        <MetricCard label="Daily DD" value={data.daily_drawdown_pct.toFixed(2) + "%"} />
        <MetricCard label="Lot Scaling (Info)" value={data.lot_scaling_factor.toFixed(2)} sub="Input to BSv3.2 — not override" />
      </div>

      {data.correlated_pairs.length > 0 && (
        <Panel title="Correlation Risk">
          <ul className="space-y-2 text-sm font-mono">
            {data.correlated_pairs.map((c, i) => (
              <li key={i} className="flex justify-between">
                <span>{c.pair.join(" / ")}</span>
                <span className="text-terminal-amber">{c.correlation.toFixed(2)}</span>
              </li>
            ))}
          </ul>
        </Panel>
      )}
    </div>
  );
}
