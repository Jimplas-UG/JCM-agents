# Daily 09:00 executive briefing + Telegram (VPS local clock should be Africa/Kampala).
$ErrorActionPreference = "Continue"
$Root = "C:\jcm-project"
$Script = "C:\Users\Administrator\vps-send-briefing-telegram.ps1"
if (-not (Test-Path "$Root\backend\.venv\Scripts\python.exe")) {
    $Root = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
}
Copy-Item (Join-Path $Root "scripts\vps-send-briefing-telegram.ps1") $Script -Force -EA SilentlyContinue
if (-not (Test-Path $Script)) {
    Copy-Item "C:\jcm-project\scripts\vps-send-briefing-telegram.ps1" $Script -Force
}

$tn = "JCM-Daily-Executive-Briefing"
schtasks /End /TN $tn 2>$null | Out-Null
schtasks /Delete /TN $tn /F 2>$null | Out-Null

$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Script`""
$result = schtasks /Create /TN $tn /TR $tr /SC DAILY /ST 09:00 /RU SYSTEM /RL HIGHEST /F 2>&1
if ($LASTEXITCODE -ne 0) { throw "schtasks create failed: $result" }
Write-Host "Task $tn registered for 09:00 daily (server local time)"
