"""Base agent interface for all supervisory agents."""

from abc import ABC, abstractmethod
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.logging_config import get_logger


class BaseAgent(ABC):
    """
    Supervisory agent base class.

    All agents observe BSv3.2 — they never override strategy logic.
    """

    name: str = "base_agent"
    description: str = ""

    def __init__(self, db: AsyncSession):
        self.db = db
        self.logger = get_logger(self.name)

    @abstractmethod
    async def run_cycle(self) -> dict[str, Any]:
        """Execute one agent cycle. Returns status/metadata."""

    async def on_event(self, event_type: str, payload: dict[str, Any]) -> None:
        """Optional hook for real-time event processing."""
        self.logger.debug("event_received", event_type=event_type)

    def _safe_float(self, value: Any, default: float = 0.0) -> float:
        if value is None:
            return default
        try:
            return float(value)
        except (TypeError, ValueError):
            return default
