import { getApiBaseUrl, getApiKey } from "@/lib/config";

function buildHeaders(json = false): HeadersInit {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (json) headers["Content-Type"] = "application/json";
  const apiKey = getApiKey();
  if (apiKey) headers["X-API-Key"] = apiKey;
  return headers;
}

export async function fetchApi<T>(path: string): Promise<T> {
  const apiUrl = getApiBaseUrl();
  const res = await fetch(`${apiUrl}${path}`, {
    cache: "no-store",
    headers: buildHeaders(),
  });
  if (!res.ok) {
    throw new Error(`API error ${res.status}: ${path}`);
  }
  return res.json();
}

export async function postApi<T>(path: string, body?: unknown): Promise<T> {
  const apiUrl = getApiBaseUrl();
  const res = await fetch(`${apiUrl}${path}`, {
    method: "POST",
    headers: buildHeaders(body !== undefined),
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`API error ${res.status}: ${path}${detail ? ` — ${detail}` : ""}`);
  }
  return res.json();
}

export const endpoints = {
  overview: "/dashboard/overview",
  trades: "/dashboard/trades",
  risk: "/dashboard/risk",
  infrastructure: "/dashboard/infrastructure",
  executionQuality: "/dashboard/execution-quality",
  performance: "/dashboard/performance",
  audit: "/dashboard/audit",
  alerts: "/dashboard/alerts",
  research: "/dashboard/research",
  briefing: "/dashboard/briefing",
  health: "/health",
  marketingBrand: "/marketing/brand",
  marketingStats: "/marketing/stats",
  marketingQueue: "/marketing/queue",
  marketingTrends: "/marketing/trends",
  marketingCycle: "/marketing/cycle",
  marketingApprove: (id: string) => `/marketing/queue/${id}/approve`,
};
