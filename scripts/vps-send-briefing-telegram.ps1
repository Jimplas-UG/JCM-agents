# Send live CEO briefing recap to Telegram (run on VPS).
$ErrorActionPreference = "Stop"
$Root = "C:\jcm-project"
$Backend = Join-Path $Root "backend"
$Py = Join-Path $Backend ".venv\Scripts\python.exe"
Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force -EA SilentlyContinue
Set-Location $Backend
& $Py -c @"
import asyncio
from app.db.session import AsyncSessionLocal
from app.agents.ceo_copilot.agent import CeoCopilotAgent
from app.services.executive_briefing.telegram import format_executive_briefing_telegram
from app.services.alerting import send_telegram_message
from app.config import get_settings

async def main():
    settings = get_settings()
    async with AsyncSessionLocal() as db:
        agent = CeoCopilotAgent(db)
        briefing = await agent.generate_daily_briefing()
        await db.commit()
    base = (settings.mission_control_public_url or '').rstrip('/')
    url = f'{base}/mission-control' if base else ''
    text = format_executive_briefing_telegram(
        briefing,
        ceo_name=settings.executive_briefing_ceo_name,
        mission_control_url=url,
    )
    ok = await send_telegram_message(text)
    print('sent' if ok else 'failed')

asyncio.run(main())
"@
