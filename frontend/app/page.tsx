"use client";

import { useCallback, useState } from "react";
import { Sidebar } from "@/components/Sidebar";
import { AlertsPanel } from "@/components/panels/AlertsPanel";
import { AnalyticsPanel } from "@/components/panels/AnalyticsPanel";
import { ExecutionPanel } from "@/components/panels/ExecutionPanel";
import { InfraPanel } from "@/components/panels/InfraPanel";
import { OverviewPanel } from "@/components/panels/OverviewPanel";
import { ResearchPanel } from "@/components/panels/ResearchPanel";
import { RiskPanel } from "@/components/panels/RiskPanel";
import { TradesPanel } from "@/components/panels/TradesPanel";
import { useWebSocket } from "@/hooks/useWebSocket";

export default function MissionControl() {
  const [section, setSection] = useState("overview");
  const [, setTick] = useState(0);

  const onWsMessage = useCallback(() => {
    setTick((t) => t + 1);
  }, []);

  const { connected } = useWebSocket(onWsMessage);

  const renderSection = () => {
    switch (section) {
      case "overview":
        return <OverviewPanel />;
      case "risk":
        return <RiskPanel />;
      case "trades":
        return <TradesPanel />;
      case "infrastructure":
        return <InfraPanel />;
      case "regime":
        return <OverviewPanel />;
      case "analytics":
        return <AnalyticsPanel />;
      case "execution":
        return <ExecutionPanel />;
      case "reports":
        return <AnalyticsPanel />;
      case "alerts":
        return (
          <div className="space-y-4">
            <AlertsPanel />
            <ResearchPanel />
          </div>
        );
      default:
        return <OverviewPanel />;
    }
  };

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar active={section} onSelect={setSection} wsConnected={connected} />
      <main className="flex-1 overflow-y-auto p-6">
        <header className="mb-6">
          <h2 className="text-lg font-semibold capitalize">
            {section.replace("-", " ")}
          </h2>
          <p className="text-xs text-terminal-muted mt-1">
            Bilshenz Strategy v3.2 — Supervisory Platform (Read-Only Observer)
          </p>
        </header>
        {renderSection()}
      </main>
    </div>
  );
}
