# Diagnose why daily briefing Telegram did not arrive (run on VPS via ssh).
$ErrorActionPreference = "Continue"
Write-Host "=== JCM Briefing Telegram diagnose ===" -ForegroundColor Cyan

Write-Host "`n[1] Scheduled task"
schtasks /Query /TN JCM-Daily-Executive-Briefing /FO LIST 2>&1

Write-Host "`n[2] Server local time"
Get-Date -Format "yyyy-MM-dd HH:mm:ss K"

Write-Host "`n[3] Telegram config in .env (masked)"
$envPath = "C:\jcm-project\.env"
if (-not (Test-Path $envPath)) { $envPath = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env" }
if (Test-Path $envPath) {
    Get-Content $envPath | Select-String -Pattern "TELEGRAM|EXECUTIVE_BRIEFING" | ForEach-Object {
        $line = $_.Line
        if ($line -match "TOKEN|KEY|SECRET") {
            $parts = $line -split "=", 2
            if ($parts.Count -eq 2) { "$($parts[0])=***set***" } else { $line }
        } else { $line }
    }
} else {
    Write-Host "  .env NOT FOUND" -ForegroundColor Red
}

Write-Host "`n[4] Briefing telegram log (last 15 lines)"
$log = "C:\logs\jcm\daily-briefing-telegram.log"
if (Test-Path $log) { Get-Content $log -Tail 15 } else { Write-Host "  (no log yet)" }

Write-Host "`n[5] Scheduler log (briefing lines)"
$sched = "C:\logs\jcm\agent-scheduler.log"
if (Test-Path $sched) {
    Select-String -Path $sched -Pattern "executive_briefing|telegram" | Select-Object -Last 10
} else {
    Write-Host "  (no scheduler log)"
}

Write-Host "`n[6] JCMAPI / JCMScheduler"
sc query JCMAPI 2>$null | findstr STATE
sc query JCMScheduler 2>$null | findstr STATE

Write-Host "`n[7] Send test now (optional - run vps-send-briefing-telegram.ps1)" -ForegroundColor Yellow
