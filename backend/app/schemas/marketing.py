"""Pydantic schemas for Marketing Agent API."""

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class MarketingContentResponse(BaseModel):
    id: UUID
    created_at: datetime
    platform: str
    content_type: str
    pillar: str | None
    title: str | None
    body: str
    hashtags: list[str]
    status: str
    scheduled_for: datetime | None
    metadata: dict

    model_config = {"from_attributes": True}


class MarketingTrendResponse(BaseModel):
    id: UUID
    created_at: datetime
    topic: str
    category: str | None
    relevance_score: float | None
    suggested_angle: str | None
    acted_on: bool

    model_config = {"from_attributes": True}


class GenerateContentRequest(BaseModel):
    pillar: str | None = None
    platform: str = "linkedin"
    run_full_cycle: bool = False


class ApproveContentRequest(BaseModel):
    approved_by: str = "human"


class BrandKitResponse(BaseModel):
    master_line: str
    channels: dict
    pillars: dict
    podcast_episodes: list


class MarketingStatsResponse(BaseModel):
    draft_count: int
    approved_count: int
    brand: BrandKitResponse
