# Deploy mission-control.html and restart JCM API.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\vps-deploy-mission-control-ui.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Jcm = "C:/Users/Administrator/Documents/JCM agents/JCM-agents"
$JcmProject = "C:/jcm-project"
$files = @(
    @{ Local = "$Root\backend\app\static\mission-control.html"; Remote = "$Jcm/backend/app/static/mission-control.html" },
    @{ Local = "$Root\backend\app\api\deps.py"; Remote = "$Jcm/backend/app/api/deps.py" },
    @{ Local = "$Root\backend\app\api\routes\dashboard.py"; Remote = "$Jcm/backend/app/api/routes/dashboard.py" },
    @{ Local = "$Root\backend\app\api\routes\marketing.py"; Remote = "$Jcm/backend/app/api/routes/marketing.py" },
    @{ Local = "$Root\backend\app\api\routes\health.py"; Remote = "$Jcm/backend/app/api/routes/health.py" },
    @{ Local = "$Root\backend\app\api\routes\mission_control_ui.py"; Remote = "$Jcm/backend/app/api/routes/mission_control_ui.py" }
)

Write-Host "=== Deploy Mission Control (fast load) ===" -ForegroundColor Cyan
foreach ($f in $files) {
    if (-not (Test-Path $f.Local)) { throw "Missing $($f.Local)" }
    Write-Host "  scp $($f.Local)"
    scp $f.Local "jcm-vps:$($f.Remote)"
    $rel = $f.Remote.Replace($Jcm, $JcmProject)
    scp $f.Local "jcm-vps:$rel" 2>$null
}

$remotePs1 = @'
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$static = Join-Path $Jcm "backend\app\static\mission-control.html"
if (-not (Test-Path $static)) { throw "Deploy failed: $static not found" }
Write-Host "Deployed: $static ($(Get-Item $static).Length bytes)"
schtasks /End /TN JCM-API-Sys 2>$null | Out-Null
Start-Sleep -Seconds 3
schtasks /Run /TN JCM-API-Sys 2>$null | Out-Null
Start-Sleep -Seconds 14
$h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 15
Write-Host "Health: $($h.status)"
'@

$tmpRemote = Join-Path $env:TEMP "vps-deploy-mc-ui-remote.ps1"
Set-Content -Path $tmpRemote -Value $remotePs1 -Encoding UTF8
scp $tmpRemote "jcm-vps:C:/Users/Administrator/deploy-mc-ui-remote.ps1"
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\deploy-mc-ui-remote.ps1"

Write-Host "Mission Control: http://104.194.140.203:8000/mission-control" -ForegroundColor Green
