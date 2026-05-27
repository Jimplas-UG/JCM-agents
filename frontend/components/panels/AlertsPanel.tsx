"use client";

import { useEffect, useState } from "react";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { endpoints, fetchApi } from "@/lib/api";

interface Alert {
  id: string;
  created_at: string;
  agent_source: string;
  severity: string;
  title: string;
  message: string;
  acknowledged: boolean;
}

export function AlertsPanel() {
  const [alerts, setAlerts] = useState<Alert[]>([]);

  useEffect(() => {
    const load = () => fetchApi<Alert[]>(endpoints.alerts).then(setAlerts).catch(() => {});
    load();
    const i = setInterval(load, 20000);
    return () => clearInterval(i);
  }, []);

  const severityStatus = (s: string): "ok" | "warning" | "error" | "neutral" => {
    if (s === "emergency" || s === "critical") return "error";
    if (s === "warning") return "warning";
    return "neutral";
  };

  return (
    <Panel title="System Alerts">
      {alerts.length === 0 ? (
        <p className="text-terminal-muted text-sm">No active alerts.</p>
      ) : (
        <ul className="space-y-3">
          {alerts.map((a) => (
            <li key={a.id} className="p-3 bg-terminal-bg rounded border border-terminal-border">
              <div className="flex items-center gap-2 mb-1">
                <StatusBadge status={severityStatus(a.severity)} label={a.severity} />
                <span className="text-xs text-terminal-muted">{a.agent_source}</span>
                <span className="text-xs text-terminal-muted ml-auto">
                  {new Date(a.created_at).toLocaleString()}
                </span>
              </div>
              <p className="font-medium text-sm">{a.title}</p>
              <p className="text-xs text-terminal-muted mt-1">{a.message}</p>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}
