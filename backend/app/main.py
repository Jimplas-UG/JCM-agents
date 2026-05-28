"""Jimplas Capital Management — BSv3.2 Supervisory Platform API."""

from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import PlainTextResponse

from app import __version__
from app.api import api_router
from app.api.deps import verify_metrics_access
from app.config import get_settings
from app.db.redis_client import close_redis
from app.logging_config import setup_logging
from app.metrics.prometheus import API_LATENCY, metrics_response
from app.middleware.security import RateLimitMiddleware, SecurityHeadersMiddleware

setup_logging()
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    issues = settings.validate_production_secrets()
    if issues:
        import logging

        log = logging.getLogger("jcm")
        for msg in issues:
            log.warning("security_config: %s", msg)
        if settings.strict_security:
            raise RuntimeError(
                "Production security misconfiguration: " + "; ".join(issues)
            )
    yield
    await close_redis()


app = FastAPI(
    title="JCM BSv3.2 Supervisory Platform",
    description=(
        "Intelligence, analytics, and infrastructure layers for Bilshenz Strategy v3.2. "
        "Observes and reports — never overrides BSv3.2 deterministic logic."
    ),
    version=__version__,
    lifespan=lifespan,
    docs_url=None if settings.is_production else "/docs",
    redoc_url=None if settings.is_production else "/redoc",
    openapi_url=None if settings.is_production else "/openapi.json",
)

app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RateLimitMiddleware, requests_per_minute=settings.rate_limit_per_minute)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.middleware("http")
async def prometheus_middleware(request: Request, call_next) -> Response:
    import time

    start = time.perf_counter()
    response = await call_next(request)
    duration = time.perf_counter() - start
    if request.url.path != settings.metrics_path:
        API_LATENCY.labels(
            endpoint=request.url.path,
            method=request.method,
        ).observe(duration)
    return response


app.include_router(api_router)


@app.get(
    settings.metrics_path,
    response_class=PlainTextResponse,
    dependencies=[Depends(verify_metrics_access)],
)
async def prometheus_metrics() -> Response:
    if not settings.prometheus_enabled:
        return PlainTextResponse("metrics disabled", status_code=404)
    return PlainTextResponse(
        content=metrics_response().decode("utf-8"),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )


@app.get("/")
async def root() -> dict:
    return {
        "service": settings.app_name,
        "version": __version__,
        "bsv32_mode": "read-only-observer",
        "docs": "/docs" if not settings.is_production else None,
    }
