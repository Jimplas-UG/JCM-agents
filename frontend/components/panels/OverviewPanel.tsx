"use client";

import { useEffect, useState } from "react";
import { MetricCard } from "@/components/MetricCard";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { endpoints, fetchApi } from "@/lib/api";

interface Overview {
  bsv32_status: string;
  system_running: boolean;
  nfp_blackout: boolean;
  live_pnl: number;
  daily_pnl: number;
  open_positions: number;
  risk_score: number;
  market_regime: string;
  infra_health_score: number;
  active_alerts: number;
  pending_reviews: number;
  pending_marketing_drafts: number;
  mt5_connected: boolean;
  last_updated: string;
}

export function OverviewPanel() {
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = () => {
    fetchApi<Overview>(endpoints.overview)
      .then(setData)
      .catch((e) => setError(e.message));
  };

  useEffect(() => {
    load();
    const interval = setInterval(load, 15000);
    return () => clearInterval(interval);
  }, []);

  if (error) {
    return (
      <Panel title="Overview">
        <p className="text-terminal-red text-sm">
          API unavailable — ensure backend is running at {process.env.NEXT_PUBLIC_API_URL}
        </p>
      </Panel>
    );
  }

  if (!data) {
    return (
      <Panel title="Overview">
        <p className="text-terminal-muted text-sm animate-pulse">Loading live data...</p>
      </Panel>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3 flex-wrap">
        <StatusBadge
          status={data.system_running ? "ok" : "warning"}
          label={`BSv3.2 ${data.bsv32_status}`}
        />
        {data.nfp_blackout && (
          <StatusBadge status="warning" label="NFP Blackout Active" />
        )}
        <StatusBadge
          status={data.mt5_connected ? "ok" : "error"}
          label={data.mt5_connected ? "MT5 Connected" : "MT5 Disconnected"}
        />
        <span className="text-xs text-terminal-muted ml-auto font-mono">
          {data.last_updated ? new Date(data.last_updated).toLocaleTimeString() : ""}
        </span>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-3">
        <MetricCard
          label="Live P&L"
          value={`$${data.live_pnl.toFixed(2)}`}
          variant={data.live_pnl >= 0 ? "positive" : "negative"}
        />
        <MetricCard
          label="Daily P&L"
          value={`$${data.daily_pnl.toFixed(2)}`}
          variant={data.daily_pnl >= 0 ? "positive" : "negative"}
        />
        <MetricCard label="Open Positions" value={data.open_positions} />
        <MetricCard
          label="Risk Score"
          value={(data.risk_score * 100).toFixed(0) + "%"}
          variant={data.risk_score > 0.7 ? "warning" : "default"}
        />
        <MetricCard label="Market Regime" value={data.market_regime} />
        <MetricCard
          label="Infra Health"
          value={(data.infra_health_score * 100).toFixed(0) + "%"}
          variant={data.infra_health_score < 0.7 ? "warning" : "positive"}
        />
        <MetricCard
          label="Active Alerts"
          value={data.active_alerts}
          variant={data.active_alerts > 0 ? "warning" : "default"}
        />
        <MetricCard label="Pending Reviews" value={data.pending_reviews} />
        <MetricCard
          label="Marketing Drafts"
          value={data.pending_marketing_drafts ?? 0}
          variant={(data.pending_marketing_drafts ?? 0) > 0 ? "warning" : "default"}
        />
      </div>

      <Panel title="TradingView — XAUUSD">
        <div className="h-[400px] bg-terminal-bg rounded border border-terminal-border flex items-center justify-center">
          <iframe
            src="https://s.tradingview.com/widgetembed/?frameElementId=tradingview&symbol=OANDA%3AXAUUSD&interval=15&hidesidetoolbar=1&theme=dark"
            className="w-full h-full rounded"
            title="TradingView Chart"
          />
        </div>
      </Panel>
    </div>
  );
}
