"""Mission Control web UI served from the public JCM API (:8000)."""

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse

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
