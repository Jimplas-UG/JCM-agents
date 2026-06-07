# Unattended execution stack ensure — every 10 minutes (SYSTEM).
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path "C:\jcm\scripts" | Out-Null

$srcEnsure = "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1"
if (-not (Test-Path $srcEnsure)) {
    $srcEnsure = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\scripts\vps-ensure-forward-bot.ps1"
}
if (-not (Test-Path $srcEnsure)) { throw "Missing vps-ensure-forward-bot.ps1" }

$destEnsure = "C:\jcm\scripts\vps-ensure-forward-bot.ps1"
if ($srcEnsure -ne $destEnsure) {
    Copy-Item $srcEnsure $destEnsure -Force
}
$tsx = "C:\jcm-project\scripts\vps-tsx-worker.ps1"
if (Test-Path $tsx) { Copy-Item $tsx "C:\jcm\scripts\vps-tsx-worker.ps1" -Force }

$tn = "JCM-Execution-Stack-Ensure"
cmd /c "schtasks /End /TN `"$tn`" 2>nul"
cmd /c "schtasks /Delete /TN `"$tn`" /F 2>nul"
$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\jcm\scripts\vps-ensure-forward-bot.ps1`""
schtasks /Create /TN $tn /TR $tr /SC MINUTE /MO 10 /RU SYSTEM /RL HIGHEST /F | Out-Null
schtasks /Run /TN $tn | Out-Null
Write-Host "Registered $tn every 10 minutes (SYSTEM)"
