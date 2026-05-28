"""Marketing Agent API — content queue, trends, brand kit."""

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.agents.marketing import MarketingAgent
from app.agents.marketing.content_engine import ContentEngine
from app.api.deps import get_db_session, verify_api_key
from app.schemas.marketing import (
    ApproveContentRequest,
    BrandKitResponse,
    GenerateContentRequest,
    MarketingContentResponse,
    MarketingStatsResponse,
    MarketingTrendResponse,
)

router = APIRouter(prefix="/marketing", tags=["marketing"])


@router.get("/brand", response_model=BrandKitResponse)
async def get_brand_kit() -> dict:
    engine = ContentEngine()
    return engine.get_brand_summary()


@router.get("/stats", response_model=MarketingStatsResponse)
async def get_marketing_stats(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = MarketingAgent(db)
    return await agent.get_stats()


@router.get("/queue", response_model=list[MarketingContentResponse])
async def get_content_queue(
    status: str | None = Query("draft"),
    platform: str | None = None,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db_session),
) -> list:
    agent = MarketingAgent(db)
    return await agent.get_queue(status=status, platform=platform, limit=limit)


@router.get("/trends", response_model=list[MarketingTrendResponse])
async def get_trends(
    limit: int = Query(20, le=100),
    db: AsyncSession = Depends(get_db_session),
) -> list:
    agent = MarketingAgent(db)
    return await agent.get_trends(limit=limit)


@router.post("/generate", dependencies=[Depends(verify_api_key)])
async def generate_content(
    body: GenerateContentRequest,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    agent = MarketingAgent(db)

    if body.run_full_cycle:
        result = await agent.run_cycle()
        return {"status": "cycle_complete", **result}

    if body.pillar:
        item = agent.engine.generate_from_pillar(body.pillar, body.platform)
        from app.models.tables import MarketingContentQueue

        row = MarketingContentQueue(
            platform=item["platform"],
            content_type=item.get("content_type", "post"),
            pillar=item.get("pillar"),
            title=item.get("title"),
            body=item["body"],
            hashtags=item.get("hashtags", []),
            status="draft",
            content_metadata={"compliance_warnings": item.get("compliance_warnings", [])},
        )
        db.add(row)
        await db.flush()
        return {"status": "created", "id": str(row.id), "title": row.title}

    rows = await agent.generate_and_queue_weekly()
    return {"status": "batch_created", "count": len(rows)}


@router.post("/cycle", dependencies=[Depends(verify_api_key)])
async def run_marketing_cycle(db: AsyncSession = Depends(get_db_session)) -> dict:
    agent = MarketingAgent(db)
    return await agent.run_cycle()


@router.post("/queue/{content_id}/approve", dependencies=[Depends(verify_api_key)])
async def approve_content(
    content_id: UUID,
    body: ApproveContentRequest,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    agent = MarketingAgent(db)
    row = await agent.approve_content(str(content_id), body.approved_by)
    if not row:
        raise HTTPException(status_code=404, detail="Content not found")
    return {
        "status": "approved",
        "id": str(row.id),
        "warnings": (row.content_metadata or {}).get("compliance_warnings", []),
    }


@router.post("/queue/{content_id}/reject", dependencies=[Depends(verify_api_key)])
async def reject_content(
    content_id: UUID,
    db: AsyncSession = Depends(get_db_session),
) -> dict:
    from sqlalchemy import select

    from app.models.tables import MarketingContentQueue

    result = await db.execute(
        select(MarketingContentQueue).where(MarketingContentQueue.id == content_id)
    )
    row = result.scalar_one_or_none()
    if not row:
        raise HTTPException(status_code=404, detail="Content not found")
    row.status = "rejected"
    await db.flush()
    return {"status": "rejected", "id": str(content_id)}
