"use client";

import { clsx } from "clsx";

const SECTIONS = [
  { id: "overview", label: "Overview" },
  { id: "risk", label: "Risk" },
  { id: "trades", label: "Active Trades" },
  { id: "infrastructure", label: "Infrastructure" },
  { id: "regime", label: "Market Regime" },
  { id: "analytics", label: "Analytics" },
  { id: "execution", label: "Execution Quality" },
  { id: "reports", label: "Historical Reports" },
  { id: "alerts", label: "System Alerts" },
];

export function Sidebar({
  active,
  onSelect,
  wsConnected,
}: {
  active: string;
  onSelect: (id: string) => void;
  wsConnected: boolean;
}) {
  return (
    <aside className="w-56 bg-terminal-panel border-r border-terminal-border flex flex-col h-screen">
      <div className="p-4 border-b border-terminal-border">
        <h1 className="text-sm font-bold tracking-tight">JCM Mission Control</h1>
        <p className="text-xs text-terminal-muted mt-0.5">BSv3.2 Supervisory</p>
        <div className="mt-2 flex items-center gap-2">
          <span
            className={clsx(
              "w-2 h-2 rounded-full",
              wsConnected ? "bg-terminal-green animate-pulse" : "bg-terminal-red"
            )}
          />
          <span className="text-xs text-terminal-muted">
            {wsConnected ? "Live" : "Reconnecting"}
          </span>
        </div>
      </div>
      <nav className="flex-1 py-2 overflow-y-auto">
        {SECTIONS.map((s) => (
          <button
            key={s.id}
            onClick={() => onSelect(s.id)}
            className={clsx(
              "w-full text-left px-4 py-2 text-sm transition-colors",
              active === s.id
                ? "bg-terminal-accent/10 text-terminal-accent border-r-2 border-terminal-accent"
                : "text-gray-400 hover:text-gray-200 hover:bg-terminal-border/50"
            )}
          >
            {s.label}
          </button>
        ))}
      </nav>
      <div className="p-4 border-t border-terminal-border text-xs text-terminal-muted">
        Observer Mode — No Override
      </div>
    </aside>
  );
}
