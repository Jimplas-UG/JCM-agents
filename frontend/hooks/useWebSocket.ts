"use client";

import { useCallback, useEffect, useRef, useState } from "react";

const WS_URL = process.env.NEXT_PUBLIC_WS_URL || "ws://localhost:8000/ws";

export interface WsMessage {
  channel: string;
  data: Record<string, unknown>;
}

export function useWebSocket(onMessage?: (msg: WsMessage) => void) {
  const [connected, setConnected] = useState(false);
  const [lastMessage, setLastMessage] = useState<WsMessage | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const pingRef = useRef<ReturnType<typeof setInterval>>();

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      pingRef.current = setInterval(() => {
        if (ws.readyState === WebSocket.OPEN) ws.send("ping");
      }, 30000);
    };

    ws.onmessage = (event) => {
      try {
        const parsed = JSON.parse(event.data);
        if (parsed.type === "pong") return;
        const msg: WsMessage = {
          channel: parsed.channel || "unknown",
          data: parsed.data || parsed,
        };
        setLastMessage(msg);
        onMessage?.(msg);
      } catch {
        /* ignore parse errors */
      }
    };

    ws.onclose = () => {
      setConnected(false);
      clearInterval(pingRef.current);
      setTimeout(connect, 5000);
    };

    ws.onerror = () => ws.close();
  }, [onMessage]);

  useEffect(() => {
    connect();
    return () => {
      clearInterval(pingRef.current);
      wsRef.current?.close();
    };
  }, [connect]);

  return { connected, lastMessage };
}
