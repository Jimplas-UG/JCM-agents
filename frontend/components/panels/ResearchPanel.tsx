"use client";

import { useEffect, useState } from "react";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { endpoints, fetchApi } from "@/lib/api";

interface Finding {
  id: string;
  created_at: string;
  title: string;
  finding_type: string;
  severity: string;
  recommendation: string;
  status: string;
  evidence: Record<string, unknown>;
}

export function ResearchPanel() {
  const [findings, setFindings] = useState<Finding[]>([]);

  useEffect(() => {
    fetchApi<Finding[]>(endpoints.research).then(setFindings).catch(() => {});
  }, []);

  return (
    <Panel title="Research Review Queue (Human-in-the-Loop)">
      <p className="text-xs text-terminal-muted mb-4">
        Recommendations only — no auto-deploy. All changes require quant team approval.
      </p>
      {findings.length === 0 ? (
        <p className="text-terminal-muted text-sm">No pending research findings.</p>
      ) : (
        <ul className="space-y-4">
          {findings.map((f) => (
            <li key={f.id} className="p-4 bg-terminal-bg rounded border border-terminal-border">
              <div className="flex items-center gap-2 mb-2">
                <StatusBadge status="warning" label={f.finding_type} />
                <span className="text-xs text-terminal-muted">{f.status}</span>
              </div>
              <p className="font-medium">{f.title}</p>
              <p className="text-sm text-terminal-muted mt-2">{f.recommendation}</p>
              <pre className="text-xs mt-2 p-2 bg-terminal-panel rounded overflow-x-auto text-terminal-muted">
                {JSON.stringify(f.evidence, null, 2)}
              </pre>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  );
}
