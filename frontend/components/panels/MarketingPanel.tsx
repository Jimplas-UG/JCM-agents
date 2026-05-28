"use client";

import { useCallback, useEffect, useState } from "react";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { endpoints, fetchApi, postApi } from "@/lib/api";

interface ContentItem {
  id: string;
  platform: string;
  content_type: string;
  pillar: string | null;
  title: string | null;
  body: string;
  status: string;
  scheduled_for: string | null;
  metadata: { compliance_warnings?: string[] };
}

interface Trend {
  id: string;
  topic: string;
  relevance_score: number | null;
  suggested_angle: string | null;
}

interface Stats {
  draft_count: number;
  approved_count: number;
}

export function MarketingPanel() {
  const [queue, setQueue] = useState<ContentItem[]>([]);
  const [trends, setTrends] = useState<Trend[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<ContentItem | null>(null);

  const load = useCallback(() => {
    Promise.all([
      fetchApi<ContentItem[]>(endpoints.marketingQueue + "?status=draft&limit=30"),
      fetchApi<Trend[]>(endpoints.marketingTrends),
      fetchApi<Stats>(endpoints.marketingStats),
    ])
      .then(([q, t, s]) => {
        setQueue(q);
        setTrends(t);
        setStats(s);
        if (q.length && !selected) setSelected(q[0]);
      })
      .catch(() => {});
  }, [selected]);

  useEffect(() => {
    load();
  }, [load]);

  const runCycle = async () => {
    setLoading(true);
    try {
      await postApi(endpoints.marketingCycle);
      load();
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
    }
  };

  const approve = async (id: string) => {
    try {
      await postApi(endpoints.marketingApprove(id), { approved_by: "ceo" });
      load();
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4 flex-wrap">
        <StatusBadge status="ok" label="Marketing Agent" />
        {stats && (
          <span className="text-sm text-terminal-muted font-mono">
            {stats.draft_count} drafts · {stats.approved_count} approved
          </span>
        )}
        <button
          onClick={runCycle}
          disabled={loading}
          className="ml-auto px-4 py-2 bg-terminal-accent text-white text-sm rounded hover:opacity-90 disabled:opacity-50"
        >
          {loading ? "Running…" : "Generate weekly batch"}
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <Panel title="Draft queue" className="lg:col-span-1">
          {queue.length === 0 ? (
            <p className="text-sm text-terminal-muted">No drafts. Run generate cycle.</p>
          ) : (
            <ul className="space-y-2 max-h-[500px] overflow-y-auto">
              {queue.map((item) => (
                <li key={item.id}>
                  <button
                    onClick={() => setSelected(item)}
                    className={`w-full text-left p-2 rounded text-sm border ${
                      selected?.id === item.id
                        ? "border-terminal-accent bg-terminal-accent/10"
                        : "border-terminal-border hover:bg-terminal-bg"
                    }`}
                  >
                    <span className="uppercase text-xs text-terminal-muted">{item.platform}</span>
                    <p className="font-medium truncate">{item.title || item.pillar}</p>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Panel>

        <Panel title="Preview" className="lg:col-span-2">
          {selected ? (
            <div className="space-y-4">
              <div className="flex gap-2 flex-wrap">
                <StatusBadge status="neutral" label={selected.platform} />
                <StatusBadge status="neutral" label={selected.content_type} />
                {selected.pillar && <StatusBadge status="neutral" label={selected.pillar} />}
              </div>
              <pre className="whitespace-pre-wrap text-sm font-sans text-gray-300 bg-terminal-bg p-4 rounded border border-terminal-border max-h-[400px] overflow-y-auto">
                {selected.body}
              </pre>
              {selected.metadata?.compliance_warnings?.length ? (
                <div className="text-sm text-terminal-amber">
                  Warnings: {selected.metadata.compliance_warnings.join("; ")}
                </div>
              ) : null}
              <button
                onClick={() => approve(selected.id)}
                className="px-4 py-2 bg-terminal-green/20 text-terminal-green border border-terminal-green rounded text-sm"
              >
                Approve for publishing
              </button>
            </div>
          ) : (
            <p className="text-terminal-muted text-sm">Select a draft to preview.</p>
          )}
        </Panel>
      </div>

      <Panel title="Trend signals">
        {trends.length === 0 ? (
          <p className="text-sm text-terminal-muted">No trends yet.</p>
        ) : (
          <ul className="space-y-2">
            {trends.map((t) => (
              <li key={t.id} className="p-3 bg-terminal-bg rounded border border-terminal-border text-sm">
                <div className="flex justify-between gap-2">
                  <span className="font-medium">{t.topic}</span>
                  {t.relevance_score != null && (
                    <span className="text-terminal-accent font-mono">
                      {(Number(t.relevance_score) * 100).toFixed(0)}%
                    </span>
                  )}
                </div>
                {t.suggested_angle && (
                  <p className="text-terminal-muted mt-1">{t.suggested_angle}</p>
                )}
              </li>
            ))}
          </ul>
        )}
      </Panel>
    </div>
  );
}
