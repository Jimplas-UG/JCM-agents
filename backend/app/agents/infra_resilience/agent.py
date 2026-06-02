"""Infrastructure Resilience Agent — self-healing VPS and API monitoring."""

import time
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from tenacity import retry, stop_after_attempt, wait_exponential

from app.agents.base import BaseAgent
from app.config import get_settings
from app.models.tables import Alert, InfraHealthLog
from app.services.agent_guard import is_allowed_outbound_url
from app.services.agent_orchestrator import log_action, publish_agent_message, reserve_remediation_slot
from app.services.alerting import AlertService


class InfrastructureResilienceAgent(BaseAgent):
    name = "infra_resilience"
    description = "Monitors VPS, MT5, APIs; self-heals and alerts on failure"

    SERVICE_ENDPOINTS = ("mt5", "desk", "forward_bot", "watchdog")

    async def run_cycle(self) -> dict[str, Any]:
        health = await self.check_all_systems()
        log = await self._persist_health(health)

        remediation = None
        if not health.get("healthy"):
            if reserve_remediation_slot():
                remediation = await self._attempt_remediation(health)
                if remediation:
                    log.remediation_action = remediation
                    await self.db.flush()
                    await publish_agent_message(
                        self.name,
                        "remediation_completed",
                        {"action": remediation, "services": health.get("services")},
                        priority="high",
                    )
            else:
                await log_action(
                    self.name,
                    "remediation_skipped_rate_limit",
                    {"failed": list(health.get("services", {}).keys())},
                    priority="high",
                )

        score = 1.0
        for svc in self.SERVICE_ENDPOINTS:
            if not health.get("services", {}).get(svc, {}).get("ok"):
                score -= 0.2
        vps = health.get("vps") or {}
        if float(vps.get("cpu_pct") or 0) > 85:
            score -= 0.1
        if float(vps.get("ram_pct") or 0) > 85:
            score -= 0.1
        infra_score = round(max(0, score), 2)

        return {
            "status": "healthy" if health.get("healthy") else "degraded",
            "health": health,
            "remediation": remediation,
            "infra_health_score": infra_score,
            "system_running": True,
        }

    async def check_all_systems(self) -> dict[str, Any]:
        settings = get_settings()
        results: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "healthy": True,
            "services": {},
        }

        async with httpx.AsyncClient(timeout=10.0) as client:
            for svc, url, key in [
                ("mt5", settings.mt5_api_url, settings.mt5_api_key),
                ("desk", settings.desk_api_url, settings.desk_api_key),
                ("forward_bot", settings.forward_bot_api_url, settings.forward_bot_api_key),
                ("watchdog", settings.watchdog_api_url, settings.watchdog_api_key),
            ]:
                status = await self._check_api(client, url, key)
                results["services"][svc] = status
                if not status.get("ok"):
                    results["healthy"] = False

        vps = await self._check_vps_metrics()
        results["vps"] = vps
        if vps.get("cpu_pct", 0) > 90 or vps.get("ram_pct", 0) > 90:
            results["healthy"] = False

        network = await self._check_network_latency()
        results["network"] = network

        return results

    async def _check_api(
        self, client: httpx.AsyncClient, base_url: str, api_key: str
    ) -> dict[str, Any]:
        start = time.perf_counter()
        try:
            headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
            resp = await client.get(f"{base_url}/health", headers=headers)
            latency_ms = int((time.perf_counter() - start) * 1000)
            return {
                "ok": resp.status_code == 200,
                "status_code": resp.status_code,
                "latency_ms": latency_ms,
            }
        except Exception as exc:
            return {"ok": False, "error": str(exc), "latency_ms": None}

    async def _check_vps_metrics(self) -> dict[str, Any]:
        """Fetch VPS metrics from Watchdog API or local agent."""
        settings = get_settings()
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                headers = {}
                if settings.watchdog_api_key:
                    headers["Authorization"] = f"Bearer {settings.watchdog_api_key}"
                resp = await client.get(
                    f"{settings.watchdog_api_url}/vps/metrics", headers=headers
                )
                if resp.status_code == 200:
                    return resp.json()
        except Exception:
            pass
        return {"cpu_pct": 0, "ram_pct": 0, "disk_pct": 0, "source": "unavailable"}

    async def _check_network_latency(self) -> dict[str, Any]:
        settings = get_settings()
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                await client.get(f"{settings.mt5_api_url}/ping")
                ping_ms = int((time.perf_counter() - start) * 1000)
                return {"ping_ms": ping_ms, "ok": ping_ms < 500}
        except Exception:
            return {"ping_ms": None, "ok": False}

    async def _persist_health(self, health: dict[str, Any]) -> InfraHealthLog:
        vps = health.get("vps", {})
        services = health.get("services", {})
        network = health.get("network", {})

        log = InfraHealthLog(
            vps_cpu_pct=Decimal(str(vps.get("cpu_pct", 0))),
            vps_ram_pct=Decimal(str(vps.get("ram_pct", 0))),
            vps_disk_pct=Decimal(str(vps.get("disk_pct", 0))),
            mt5_connected=services.get("mt5", {}).get("ok"),
            mt5_latency_ms=services.get("mt5", {}).get("latency_ms"),
            desk_api_ok=services.get("desk", {}).get("ok"),
            desk_api_latency_ms=services.get("desk", {}).get("latency_ms"),
            forward_bot_ok=services.get("forward_bot", {}).get("ok"),
            forward_bot_latency_ms=services.get("forward_bot", {}).get("latency_ms"),
            watchdog_ok=services.get("watchdog", {}).get("ok"),
            network_ping_ms=network.get("ping_ms"),
            service_states=services,
            alert_triggered=not health.get("healthy", True),
        )
        self.db.add(log)
        await self.db.flush()

        if not health.get("healthy"):
            await self._raise_infra_alert(health)
        return log

    async def _raise_infra_alert(self, health: dict[str, Any]) -> None:
        failed = [
            k for k, v in health.get("services", {}).items() if not v.get("ok")
        ]
        alert_svc = AlertService(self.db)
        await alert_svc.create_alert(
            agent_source=self.name,
            severity="critical",
            title="Infrastructure Degradation Detected",
            message=f"Failed services: {', '.join(failed) or 'VPS metrics'}",
            metadata=health,
        )

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=30),
    )
    async def _attempt_remediation(self, health: dict[str, Any]) -> str | None:
        settings = get_settings()
        failed_services = [
            k for k, v in health.get("services", {}).items() if not v.get("ok")
        ]

        if not failed_services:
            return None

        action_taken = []
        async with httpx.AsyncClient(timeout=15.0) as client:
            for svc in failed_services:
                url = f"{settings.watchdog_api_url}/remediate/{svc}"
                if not is_allowed_outbound_url(url):
                    self.logger.warning("remediation_url_blocked", service=svc, url=url)
                    continue
                try:
                    resp = await client.post(
                        url,
                        headers={"Authorization": f"Bearer {settings.watchdog_api_key}"},
                    )
                    if resp.status_code == 200:
                        action_taken.append(f"restarted_{svc}")
                except Exception as exc:
                    self.logger.warning("remediation_failed", service=svc, error=str(exc))

            if "mt5" in failed_services:
                mt5_url = f"{settings.mt5_api_url}/reconnect"
                if is_allowed_outbound_url(mt5_url):
                    try:
                        await client.post(
                            mt5_url,
                            headers={"Authorization": f"Bearer {settings.mt5_api_key}"},
                        )
                        action_taken.append("mt5_reconnect")
                    except Exception:
                        pass

        return ",".join(action_taken) if action_taken else None

    async def get_latest_health(self) -> InfraHealthLog | None:
        result = await self.db.execute(
            select(InfraHealthLog).order_by(InfraHealthLog.created_at.desc()).limit(1)
        )
        return result.scalar_one_or_none()
