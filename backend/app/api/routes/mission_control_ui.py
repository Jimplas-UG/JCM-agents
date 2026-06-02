"""Mission Control web UI served from the public JCM API (:8000)."""

from pathlib import Path

from fastapi import APIRouter, Depends
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse

from app.api.deps import verify_mission_control_access
from app.services.ws_auth import create_ws_token

STATIC_DIR = Path(__file__).resolve().parents[2] / "static"
MC_HTML = STATIC_DIR / "mission-control.html"
LOGO = STATIC_DIR / "bs-logo.png"

router = APIRouter(tags=["mission-control-ui"])


@router.get("/mission-control/logo")
async def mission_control_logo() -> FileResponse:
    return FileResponse(LOGO, media_type="image/png")


@router.get("/mission-control", response_class=HTMLResponse)
async def mission_control_page() -> FileResponse:
    return FileResponse(MC_HTML, media_type="text/html; charset=utf-8")


@router.get("/dashboard-ui")
async def dashboard_ui_redirect() -> RedirectResponse:
    """Alias for bookmarks and Bilshenz integrations."""
    return RedirectResponse(url="/mission-control", status_code=302)


@router.post("/mission-control/ws-token")
async def mission_control_ws_token(
    _: None = Depends(verify_mission_control_access),
) -> dict:
    """Issue short-lived WebSocket token after Mission Control sign-in."""
    from app.config import get_settings

    settings = get_settings()
    user = settings.mission_control_user or "ceo"
    return {
        "token": create_ws_token(user),
        "expires_in_seconds": getattr(settings, "ws_token_ttl_seconds", 3600),
    }
