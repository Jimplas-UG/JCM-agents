"""Alert dispatch service — Telegram and email notifications."""

from typing import Any

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.redis_client import CHANNEL_ALERTS, publish
from app.logging_config import get_logger
from app.models.tables import Alert

logger = get_logger("alerting")


class AlertService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_alert(
        self,
        agent_source: str,
        severity: str,
        title: str,
        message: str,
        metadata: dict[str, Any] | None = None,
    ) -> Alert:
        import json

        alert = Alert(
            agent_source=agent_source,
            severity=severity,
            title=title,
            message=message,
            alert_metadata=metadata or {},
        )
        self.db.add(alert)
        await self.db.flush()

        await publish(
            CHANNEL_ALERTS,
            json.dumps({
                "id": str(alert.id),
                "severity": severity,
                "title": title,
                "agent": agent_source,
            }),
        )

        if severity in ("critical", "emergency"):
            await self._send_telegram(title, message)
            await self._send_email(title, message)
            alert.telegram_sent = True
            alert.email_sent = True
            await self.db.flush()

        logger.info("alert_created", title=title, severity=severity, agent=agent_source)
        return alert

    async def _send_telegram(self, title: str, message: str) -> None:
        settings = get_settings()
        if not settings.telegram_bot_token or not settings.telegram_chat_id:
            return
        text = f"*{title}*\n{message}"
        url = f"https://api.telegram.org/bot{settings.telegram_bot_token}/sendMessage"
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                await client.post(
                    url,
                    json={
                        "chat_id": settings.telegram_chat_id,
                        "text": text,
                        "parse_mode": "Markdown",
                    },
                )
        except Exception as exc:
            logger.warning("telegram_send_failed", error=str(exc))

    async def _send_email(self, title: str, message: str) -> None:
        settings = get_settings()
        if not settings.alert_email_smtp_host:
            return
        try:
            import asyncio

            await asyncio.to_thread(self._send_email_sync, title, message, settings)
        except Exception as exc:
            logger.warning("email_send_failed", error=str(exc))

    @staticmethod
    def _send_email_sync(title: str, message: str, settings: object) -> None:
        import smtplib
        from email.mime.text import MIMEText

        msg = MIMEText(message)
        msg["Subject"] = f"[JCM Alert] {title}"
        msg["From"] = settings.alert_email_from  # type: ignore[attr-defined]
        msg["To"] = settings.alert_email_to  # type: ignore[attr-defined]

        with smtplib.SMTP(
            settings.alert_email_smtp_host,  # type: ignore[attr-defined]
            settings.alert_email_smtp_port,  # type: ignore[attr-defined]
        ) as server:
            server.starttls()
            if settings.alert_email_password:  # type: ignore[attr-defined]
                server.login(
                    settings.alert_email_from,  # type: ignore[attr-defined]
                    settings.alert_email_password,  # type: ignore[attr-defined]
                )
            server.send_message(msg)
