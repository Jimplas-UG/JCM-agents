/**
 * API base URL for the dashboard.
 * In the browser we always use same-origin /jcm-api (Next.js rewrites to localhost:8000).
 * This avoids blocked port 8000, CORS, and baked-in localhost URLs.
 */

const PROXY_PREFIX = "/jcm-api";

export function getApiBaseUrl(): string {
  if (typeof window !== "undefined") {
    return `${window.location.origin}${PROXY_PREFIX}`;
  }
  return process.env.NEXT_PUBLIC_API_URL || "http://localhost:8000";
}

export function getWsUrl(): string {
  if (typeof window !== "undefined") {
    const { protocol, hostname } = window.location;
    const wsProto = protocol === "https:" ? "wss:" : "ws:";
    // WebSocket cannot use Next rewrites; hit API port on same host as the page.
    const port = process.env.NEXT_PUBLIC_API_PORT || "8000";
    return `${wsProto}//${hostname}:${port}/ws`;
  }
  return process.env.NEXT_PUBLIC_WS_URL || "ws://localhost:8000/ws";
}

export function getApiKey(): string {
  return process.env.NEXT_PUBLIC_API_KEY || "";
}
