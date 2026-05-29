# Deploy backend UI + observability stack to VPS
$ErrorActionPreference = "Continue"
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Admin = "C:\Users\Administrator"

New-Item -ItemType Directory -Force -Path "$Jcm\backend\app\static" | Out-Null
Copy-Item "$Admin\vps-install-system-tasks.ps1" "$Jcm\scripts\" -Force
Copy-Item "$Admin\run-jcm-observability-stack.ps1" "$Jcm\scripts\" -Force
Copy-Item "$Admin\mission_control_ui.py" "$Jcm\backend\app\api\routes\" -Force
Copy-Item "$Admin\mission-control.html" "$Jcm\backend\app\static\" -Force
Copy-Item "$Admin\__init__.py" "$Jcm\backend\app\api\" -Force
Copy-Item "$Admin\main.py" "$Jcm\backend\app\" -Force

if (-not (Test-Path "C:\jcm-project")) {
    cmd /c "mklink /J C:\jcm-project `"$Jcm`""
}
icacls "C:\jcm-project" /grant "SYSTEM:(OI)(CI)RX" /T /C 2>$null | Out-Null
icacls "C:\jcm" /grant "SYSTEM:(OI)(CI)F" /T /C 2>$null | Out-Null

& "$Admin\vps-install-system-tasks.ps1"

schtasks /End /TN JCM-API-Sys 2>$null
Start-Sleep -Seconds 3
schtasks /Run /TN JCM-API-Sys 2>$null
Start-Sleep -Seconds 15

try {
    $r = Invoke-WebRequest "http://127.0.0.1:8000/mission-control" -UseBasicParsing -TimeoutSec 10
    Write-Host "Mission Control UI: HTTP $($r.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "Mission Control UI check failed: $_" -ForegroundColor Yellow
}

& "$Admin\vps-live-test.ps1"
Write-Host "`nPublic dashboard: http://104.194.140.203:8000/mission-control" -ForegroundColor Green
