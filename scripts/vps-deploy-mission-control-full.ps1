# Deploy full mission control + agent scheduler
$ErrorActionPreference = "Continue"
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Admin = "C:\Users\Administrator"

New-Item -ItemType Directory -Force -Path "$Jcm\backend\app\static" | Out-Null
Copy-Item "$Admin\mission-control.html" "$Jcm\backend\app\static\" -Force -EA SilentlyContinue
Copy-Item "$Admin\health.py" "$Jcm\backend\app\api\routes\" -Force -EA SilentlyContinue
Copy-Item "$Admin\run-jcm-agents.ps1" "$Jcm\scripts\" -Force -EA SilentlyContinue
Copy-Item "$Admin\vps-install-system-tasks.ps1" "$Jcm\scripts\" -Force -EA SilentlyContinue

# Also copy from repo if running from repo path
if (Test-Path "$Jcm\backend\app\static\mission-control.html") {
    Copy-Item "$Jcm\backend\app\static\mission-control.html" "$Jcm\backend\app\static\" -Force
}

schtasks /End /TN JCM-API-Sys 2>$null | Out-Null
Start-Sleep -Seconds 3
schtasks /Run /TN JCM-API-Sys 2>$null | Out-Null
Start-Sleep -Seconds 10

if (Test-Path "$Jcm\scripts\vps-install-system-tasks.ps1") {
    & "$Jcm\scripts\vps-install-system-tasks.ps1"
}

Write-Host "Mission Control: http://104.194.140.203:8000/mission-control" -ForegroundColor Green
