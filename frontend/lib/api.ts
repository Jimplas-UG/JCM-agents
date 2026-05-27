const API_URL = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";

export async function fetchApi<T>(path: string): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    cache: "no-store",
    headers: { Accept: "application/json" },
  });
  if (!res.ok) {
    throw new Error(`API error ${res.status}: ${path}`);
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
};
