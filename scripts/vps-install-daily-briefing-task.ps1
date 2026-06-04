# Daily 09:00 executive briefing + Telegram (server local time = Africa/Kampala after tz script).
$ErrorActionPreference = "Stop"
$LogDir = "C:\logs\jcm"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$Root = "C:\jcm-project"
$Script = "C:\Users\Administrator\vps-send-briefing-telegram.ps1"
if (-not (Test-Path "$Root\backend\.venv\Scripts\python.exe")) {
    $Root = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
}
$src = Join-Path $Root "scripts\vps-send-briefing-telegram.ps1"
if (Test-Path $src) {
    Copy-Item $src $Script -Force
} elseif (-not (Test-Path $Script)) {
    throw "vps-send-briefing-telegram.ps1 not found"
}

$tn = "JCM-Daily-Executive-Briefing"
schtasks /End /TN $tn 2>$null | Out-Null
schtasks /Delete /TN $tn /F 2>$null | Out-Null

# Run as Administrator (not SYSTEM) so .env and paths match interactive deploys.
$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script`""
$result = schtasks /Create /TN $tn /TR $tr /SC DAILY /ST 09:00 /RU Administrator /RL HIGHEST /F 2>&1
if ($LASTEXITCODE -ne 0) {
    # Fallback if Administrator requires password on this host
    $result = schtasks /Create /TN $tn /TR $tr /SC DAILY /ST 09:00 /RL HIGHEST /F 2>&1
}
if ($LASTEXITCODE -ne 0) { throw "schtasks create failed: $result" }

Write-Host "Task $tn registered for 09:00 daily (server local time)"
Write-Host "Log: $LogDir\daily-briefing-telegram.log"
schtasks /Query /TN $tn /FO LIST | findstr /I "TaskName Status Next"
