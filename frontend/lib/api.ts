const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
const API_KEY = process.env.NEXT_PUBLIC_API_KEY || "";

function buildHeaders(json = false): HeadersInit {
  const headers: Record<string, string> = { Accept: "application/json" };
  if (json) headers["Content-Type"] = "application/json";
  if (API_KEY) headers["X-API-Key"] = API_KEY;
  return headers;
}

export async function fetchApi<T>(path: string): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    cache: "no-store",
    headers: buildHeaders(),
  });
  if (!res.ok) {
    throw new Error(`API error ${res.status}: ${path}`);
  }
  return res.json();
}

export async function postApi<T>(path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
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
