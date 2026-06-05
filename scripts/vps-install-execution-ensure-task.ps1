# Unattended execution stack ensure — every 30 minutes (SYSTEM).
$ErrorActionPreference = "Stop"
$ensure = "C:\jcm\scripts\vps-ensure-forward-bot.ps1"
if (-not (Test-Path $ensure)) {
    $ensure = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\scripts\vps-ensure-forward-bot.ps1"
}
if (-not (Test-Path $ensure)) { throw "Missing vps-ensure-forward-bot.ps1" }
Copy-Item $ensure "C:\jcm\scripts\vps-ensure-forward-bot.ps1" -Force -EA SilentlyContinue

$tn = "JCM-Execution-Stack-Ensure"
cmd /c "schtasks /End /TN `"$tn`" 2>nul"
cmd /c "schtasks /Delete /TN `"$tn`" /F 2>nul"
$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\jcm\scripts\vps-ensure-forward-bot.ps1`""
schtasks /Create /TN $tn /TR $tr /SC MINUTE /MO 30 /RU SYSTEM /RL HIGHEST /F | Out-Null
schtasks /Run /TN $tn | Out-Null
Write-Host "Registered $tn every 30 minutes (SYSTEM)"
