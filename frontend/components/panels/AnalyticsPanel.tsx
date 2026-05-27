"use client";

import { useEffect, useState } from "react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { MetricCard } from "@/components/MetricCard";
import { Panel } from "@/components/Panel";
import { endpoints, fetchApi } from "@/lib/api";

interface PerfData {
  report_date: string;
  total_trades: number;
  win_rate: number | null;
  expectancy: number | null;
  avg_r_multiple: number | null;
  total_pnl_usd: number | null;
  edge_decay_score: number | null;
  anomaly_flags: string[];
}

export function AnalyticsPanel() {
  const [perf, setPerf] = useState<PerfData | null>(null);

  useEffect(() => {
    fetchApi<PerfData | null>(endpoints.performance).then(setPerf).catch(() => {});
  }, []);

  const chartData = perf
    ? [
        { name: "Win Rate", value: (perf.win_rate ?? 0) * 100 },
        { name: "Expectancy", value: perf.expectancy ?? 0 },
        { name: "Avg R", value: perf.avg_r_multiple ?? 0 },
        { name: "Edge Decay", value: (perf.edge_decay_score ?? 0) * 100 },
      ]
    : [];

  return (
    <div className="space-y-4">
      {perf ? (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
            <MetricCard label="Trades Today" value={perf.total_trades} />
            <MetricCard label="Win Rate" value={((perf.win_rate ?? 0) * 100).toFixed(1) + "%"} />
            <MetricCard label="Expectancy" value={`$${(perf.expectancy ?? 0).toFixed(2)}`} />
            <MetricCard label="Edge Decay" value={((perf.edge_decay_score ?? 0) * 100).toFixed(1) + "%"} variant={(perf.edge_decay_score ?? 0) > 0.3 ? "warning" : "default"} />
          </div>

          <Panel title="Performance Metrics">
            <ResponsiveContainer width="100%" height={250}>
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#1f2937" />
                <XAxis dataKey="name" stroke="#6b7280" fontSize={12} />
                <YAxis stroke="#6b7280" fontSize={12} />
                <Tooltip contentStyle={{ background: "#111827", border: "1px solid #1f2937" }} />
                <Bar dataKey="value" fill="#3b82f6" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </Panel>

          {perf.anomaly_flags?.length > 0 && (
            <Panel title="Anomaly Flags">
              <ul className="text-sm text-terminal-amber space-y-1">
                {perf.anomaly_flags.map((f) => (
                  <li key={f}>⚠ {f}</li>
                ))}
              </ul>
            </Panel>
          )}
        </>
      ) : (
        <Panel title="Analytics">
          <p className="text-terminal-muted text-sm">
            No performance report for today. POST /dashboard/performance/generate to create one.
          </p>
        </Panel>
      )}
    </div>
  );
}
