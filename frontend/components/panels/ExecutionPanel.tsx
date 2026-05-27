"use client";

import { useEffect, useState } from "react";
import { MetricCard } from "@/components/MetricCard";
import { Panel } from "@/components/Panel";
import { endpoints, fetchApi } from "@/lib/api";

interface ExecData {
  sample_size: number;
  avg_slippage_pips?: number;
  avg_fill_speed_ms?: number;
  rejection_rate?: number;
  anomaly_count?: number;
  slippage_trend?: { recent_avg: number; prior_avg: number; worsening: boolean };
  recommendation?: string;
  message?: string;
}

export function ExecutionPanel() {
  const [data, setData] = useState<ExecData | null>(null);

  useEffect(() => {
    const load = () => fetchApi<ExecData>(endpoints.executionQuality).then(setData).catch(() => {});
    load();
    const i = setInterval(load, 60000);
    return () => clearInterval(i);
  }, []);

  if (!data) return <Panel title="Execution Quality"><p className="text-terminal-muted text-sm">Loading...</p></Panel>;

  if (data.message) {
    return <Panel title="Execution Quality"><p className="text-terminal-muted text-sm">{data.message}</p></Panel>;
  }

  return (
    <div className="space-y-4">
      {data.recommendation && (
        <div className="bg-terminal-amber/10 border border-terminal-amber rounded p-3 text-sm text-terminal-amber">
          {data.recommendation}
        </div>
      )}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <MetricCard label="Sample (24h)" value={data.sample_size} />
        <MetricCard label="Avg Slippage" value={(data.avg_slippage_pips ?? 0).toFixed(2) + " pips"} variant={data.slippage_trend?.worsening ? "warning" : "default"} />
        <MetricCard label="Fill Speed" value={(data.avg_fill_speed_ms ?? 0).toFixed(0) + " ms"} />
        <MetricCard label="Rejections" value={((data.rejection_rate ?? 0) * 100).toFixed(1) + "%"} />
        <MetricCard label="Anomalies" value={data.anomaly_count ?? 0} variant={(data.anomaly_count ?? 0) > 0 ? "warning" : "default"} />
      </div>
    </div>
  );
}
