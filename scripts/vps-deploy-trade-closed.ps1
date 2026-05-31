# Deploy trade_closed webhook wiring (Bilshenz observability + JCM ingest) — no strategy changes.
# Requires ssh jcm-vps (see scripts/setup-local-vps-access.ps1).
#
# From repo root:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\vps-deploy-trade-closed.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Jcm = "C:/Users/Administrator/Documents/JCM agents/JCM-agents"
$Bilshenz = "C:/opt/bilshenz"

Write-Host "=== Deploy trade_closed wiring ===" -ForegroundColor Cyan

$files = @(
    @{ Local = "$Root\infra\bilshenz\jcm\jcmSupervisorPublisher.ts"; Remote = "$Jcm/infra/bilshenz/jcm/jcmSupervisorPublisher.ts" },
    @{ Local = "$Root\infra\bilshenz\jcm\jcmPositionWatcher.ts"; Remote = "$Jcm/infra/bilshenz/jcm/jcmPositionWatcher.ts" },
    @{ Local = "$Root\infra\bilshenz\run-forward-demo-30d.ts"; Remote = "$Jcm/infra/bilshenz/run-forward-demo-30d.ts" },
    @{ Local = "$Root\backend\app\agents\quant_memory\agent.py"; Remote = "$Jcm/backend/app/agents/quant_memory/agent.py" },
    @{ Local = "$Root\backend\app\agents\explainability\agent.py"; Remote = "$Jcm/backend/app/agents/explainability/agent.py" },
    @{ Local = "$Root\backend\app\services\event_pipeline.py"; Remote = "$Jcm/backend/app/services/event_pipeline.py" },
    @{ Local = "$Root\backend\app\schemas\events.py"; Remote = "$Jcm/backend/app/schemas/events.py" },
    @{ Local = "$Root\backend\app\static\mission-control.html"; Remote = "$Jcm/backend/app/static/mission-control.html" }
)

foreach ($f in $files) {
    if (-not (Test-Path $f.Local)) { throw "Missing $($f.Local)" }
    Write-Host "  scp $($f.Local) -> jcm-vps:$($f.Remote)"
    scp $f.Local "jcm-vps:$($f.Remote)"
}

$remotePs1 = @'
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Bilshenz = "C:\opt\bilshenz"
New-Item -ItemType Directory -Force -Path "$Bilshenz\backend\jcm" | Out-Null
Copy-Item "$Jcm\infra\bilshenz\jcm\jcmSupervisorPublisher.ts" "$Bilshenz\backend\jcm\" -Force
Copy-Item "$Jcm\infra\bilshenz\jcm\jcmPositionWatcher.ts" "$Bilshenz\backend\jcm\" -Force
Copy-Item "$Jcm\infra\bilshenz\run-forward-demo-30d.ts" "$Bilshenz\backend\scripts\" -Force
Write-Host "Bilshenz JCM files installed"
schtasks /End /TN Bilshenz-ForwardBot-Sys 2>$null
Start-Sleep -Seconds 3
schtasks /Run /TN Bilshenz-ForwardBot-Sys 2>$null
schtasks /End /TN JCM-API-Sys 2>$null
Start-Sleep -Seconds 3
schtasks /Run /TN JCM-API-Sys 2>$null
Start-Sleep -Seconds 12
Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 10 | Out-Null
Write-Host "Health OK"
'@

$tmpRemote = Join-Path $env:TEMP "vps-deploy-trade-closed-remote.ps1"
Set-Content -Path $tmpRemote -Value $remotePs1 -Encoding UTF8
scp $tmpRemote "jcm-vps:C:/Users/Administrator/vps-deploy-trade-closed-remote.ps1"
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-deploy-trade-closed-remote.ps1"

Write-Host ""
Write-Host "Mission Control: http://104.194.140.203:8000/mission-control" -ForegroundColor Green
Write-Host "Trades API:      http://104.194.140.203:8000/dashboard/trades" -ForegroundColor Green
