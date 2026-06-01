"use client";

import { useEffect, useState } from "react";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { endpoints, fetchApi } from "@/lib/api";

interface SubscriptionItem {
  id: string;
  label: string;
  expires_on: string;
  display_date?: string;
  days_left?: number;
  status?: string;
  plan?: string;
  notes?: string;
}

interface InfraData {
  current?: {
    healthy: boolean;
    services: Record<string, { ok: boolean; latency_ms?: number }>;
    vps: { cpu_pct: number; ram_pct: number; disk_pct: number };
    network?: { ping_ms?: number; ok: boolean };
  };
  subscriptions?: { subscriptions: SubscriptionItem[] };
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
  const subs = data.subscriptions?.subscriptions ?? [];

  const subStatus = (s: SubscriptionItem) => {
    if (s.status === "expired" || s.status === "urgent") return "error";
    if (s.status === "soon") return "warn";
    return "ok";
  };

  const subscriptionPanel =
    subs.length > 0 ? (
      <Panel title="Subscription renewals">
        <div className="space-y-2">
          {subs.map((s) => (
            <div key={s.id} className="flex items-center justify-between p-2 bg-terminal-bg rounded text-sm">
              <div>
                <p className="font-medium">{s.label}</p>
                <p className="text-terminal-muted text-xs">
                  Expires {s.display_date || s.expires_on}
                  {s.days_left != null && ` · ${s.days_left} days left`}
                </p>
              </div>
              <StatusBadge status={subStatus(s)} label={(s.status || "ok").toUpperCase()} />
            </div>
          ))}
        </div>
      </Panel>
    ) : null;

  return (
    <div className="space-y-4">
      {!current ? (
        <>
          <Panel title="Infrastructure">
            <p className="text-terminal-muted text-sm">Health metrics loading…</p>
          </Panel>
          {subscriptionPanel}
        </>
      ) : (
        <>
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

          {subscriptionPanel}
        </>
      )}
    </div>
  );
}
