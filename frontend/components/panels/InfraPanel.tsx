"use client";

import { useEffect, useState } from "react";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { endpoints, fetchApi } from "@/lib/api";

interface InfraData {
  current: {
    healthy: boolean;
    services: Record<string, { ok: boolean; latency_ms?: number }>;
    vps: { cpu_pct: number; ram_pct: number; disk_pct: number };
    network: { ping_ms?: number; ok: boolean };
  };
}

export function InfraPanel() {
  const [data, setData] = useState<InfraData | null>(null);

  useEffect(() => {
    const load = () => fetchApi<InfraData>(endpoints.infrastructure).then(setData).catch(() => {});
    load();
    const i = setInterval(load, 30000);
    return () => clearInterval(i);
  }, []);

  if (!data) return <Panel title="Infrastructure"><p className="text-terminal-muted text-sm">Loading...</p></Panel>;

  const { current } = data;

  return (
    <div className="space-y-4">
      <StatusBadge status={current.healthy ? "ok" : "error"} label={current.healthy ? "All Systems Operational" : "Degraded"} />

      <Panel title="API Services">
        <div className="grid grid-cols-2 gap-3">
          {Object.entries(current.services || {}).map(([name, svc]) => (
            <div key={name} className="flex items-center justify-between p-2 bg-terminal-bg rounded">
              <span className="text-sm uppercase">{name}</span>
              <StatusBadge status={svc.ok ? "ok" : "error"} label={svc.ok ? `${svc.latency_ms ?? "—"}ms` : "DOWN"} />
            </div>
          ))}
        </div>
      </Panel>

      <Panel title="VPS Metrics">
        <div className="grid grid-cols-3 gap-4 font-mono text-sm">
          {(["cpu_pct", "ram_pct", "disk_pct"] as const).map((key) => (
            <div key={key}>
              <p className="text-terminal-muted text-xs uppercase">{key.replace("_pct", "")}</p>
              <p className={`text-xl ${(current.vps?.[key] ?? 0) > 85 ? "text-terminal-red" : ""}`}>
                {(current.vps?.[key] ?? 0).toFixed(1)}%
              </p>
            </div>
          ))}
        </div>
      </Panel>
    </div>
  );
}
