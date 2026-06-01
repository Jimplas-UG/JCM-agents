# Deploy mission-control.html and restart JCM API.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File scripts\vps-deploy-mission-control-ui.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Jcm = "C:/Users/Administrator/Documents/JCM agents/JCM-agents"
$Local = "$Root\backend\app\static\mission-control.html"
$Remote = "$Jcm/backend/app/static/mission-control.html"

if (-not (Test-Path $Local)) { throw "Missing $Local" }

Write-Host "=== Deploy Mission Control UI ===" -ForegroundColor Cyan
Write-Host "  scp -> jcm-vps:$Remote"
scp $Local "jcm-vps:$Remote"

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
