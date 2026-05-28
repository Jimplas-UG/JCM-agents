from fastapi import APIRouter

from app.api.routes import dashboard, health, ingest, marketing, websocket

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(ingest.router)
api_router.include_router(dashboard.router)
api_router.include_router(marketing.router)
api_router.include_router(websocket.router)
