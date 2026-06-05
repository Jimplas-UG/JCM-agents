# Permanent executive briefing delivery — deploy from dev machine.
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Root = "C:/jcm-project"

$backendFiles = @(
    "backend/app/workers/daily_briefing_delivery.py",
    "backend/app/workers/daily_briefing_job.py",
    "backend/app/workers/briefing_scheduler_embedded.py",
    "backend/app/workers/agent_scheduler.py",
    "backend/app/main.py",
    "backend/app/services/alerting.py"
)
foreach ($f in $backendFiles) {
    scp (Join-Path $Repo $f) "jcm-vps:$Root/$($f -replace '\\','/')"
}

$scripts = @(
    "vps-briefing-common.ps1",
    "vps-send-briefing-telegram.ps1",
    "vps-briefing-backup.ps1",
    "vps-briefing-startup-catchup.ps1",
    "run-briefing-primary.bat",
    "run-briefing-backup.bat",
    "run-briefing-startup-catchup.bat",
    "vps-install-briefing-pipeline.ps1",
    "vps-scheduler-watchdog.ps1",
    "vps-install-scheduler-watchdog-task.ps1"
)
foreach ($s in $scripts) {
    scp (Join-Path $Repo "scripts\$s") "jcm-vps:C:/Users/Administrator/$s"
    scp (Join-Path $Repo "scripts\$s") "jcm-vps:$Root/scripts/$s"
}

Write-Host "Installing briefing tasks (09:00 + 09:15 backup)..." -ForegroundColor Cyan
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-install-briefing-pipeline.ps1"

Write-Host "Restarting JCMAPI (embedded 09:00 scheduler)..." -ForegroundColor Cyan
ssh jcm-vps "C:\jcm\nssm\nssm.exe restart JCMAPI confirm"

Write-Host "Sending briefing now..." -ForegroundColor Cyan
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-send-briefing-telegram.ps1"

Write-Host "Done. Check Telegram and C:\logs\jcm\daily-briefing-telegram.log on VPS." -ForegroundColor Green
