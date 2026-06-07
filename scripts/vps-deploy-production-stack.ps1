# Production stack deploy: forward + watchdog + briefing + ensure task.
# Run locally: powershell -File scripts\vps-deploy-production-stack.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$HostName = if ($env:VPS_HOST) { $env:VPS_HOST } else { "jcm-vps" }
$Jcm = "C:/jcm-project"
$Bilshenz = "C:/opt/bilshenz"

Write-Host "=== Deploy production stack to $HostName ===" -ForegroundColor Cyan

$files = @(
    @{ Local = "$Root\run-forward-bot.vps.ps1"; Remote = "$Jcm/run-forward-bot.vps.ps1" },
    @{ Local = "$Root\run-watchdog.vps.ps1"; Remote = "$Jcm/run-watchdog.vps.ps1" },
    @{ Local = "$Root\watchdog.vps.ts"; Remote = "$Jcm/watchdog.vps.ts" },
    @{ Local = "$Root\watchdog.vps.ts"; Remote = "$Bilshenz/deploy/watchdog.ts" },
    @{ Local = "$Root\scripts\vps-tsx-worker.ps1"; Remote = "$Jcm/scripts/vps-tsx-worker.ps1" },
    @{ Local = "$Root\scripts\vps-ensure-forward-bot.ps1"; Remote = "$Jcm/scripts/vps-ensure-forward-bot.ps1" },
    @{ Local = "$Root\scripts\vps-install-execution-ensure-task.ps1"; Remote = "$Jcm/scripts/vps-install-execution-ensure-task.ps1" },
    @{ Local = "$Root\scripts\vps-install-briefing-pipeline.ps1"; Remote = "$Jcm/scripts/vps-install-briefing-pipeline.ps1" },
    @{ Local = "$Root\scripts\vps-briefing-common.ps1"; Remote = "$Jcm/scripts/vps-briefing-common.ps1" },
    @{ Local = "$Root\scripts\vps-send-briefing-telegram.ps1"; Remote = "$Jcm/scripts/vps-send-briefing-telegram.ps1" },
    @{ Local = "$Root\scripts\vps-briefing-backup.ps1"; Remote = "$Jcm/scripts/vps-briefing-backup.ps1" },
    @{ Local = "$Root\scripts\vps-briefing-startup-catchup.ps1"; Remote = "$Jcm/scripts/vps-briefing-startup-catchup.ps1" },
    @{ Local = "$Root\scripts\vps-test-forward-watchdog.ps1"; Remote = "C:/Users/Administrator/vps-test-forward-watchdog.ps1" }
)
foreach ($f in $files) {
    if (-not (Test-Path $f.Local)) { throw "Missing $($f.Local)" }
    Write-Host "  scp -> $($f.Remote)"
    scp $f.Local "${HostName}:$($f.Remote)"
}

$remotePs1 = @'
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path "C:\jcm\scripts" | Out-Null
Copy-Item "C:\jcm-project\run-forward-bot.vps.ps1" "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -Force
Copy-Item "C:\jcm-project\run-watchdog.vps.ps1" "C:\opt\bilshenz\deploy\windows\run-watchdog.ps1" -Force
Copy-Item "C:\jcm-project\scripts\vps-tsx-worker.ps1" "C:\opt\bilshenz\deploy\windows\vps-tsx-worker.ps1" -Force
Copy-Item "C:\jcm-project\watchdog.vps.ts" "C:\opt\bilshenz\deploy\watchdog.ts" -Force
Copy-Item "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1" "C:\jcm\scripts\" -Force
Copy-Item "C:\jcm-project\scripts\vps-tsx-worker.ps1" "C:\jcm\scripts\" -Force

& "C:\jcm-project\scripts\vps-install-execution-ensure-task.ps1"
& "C:\jcm-project\scripts\vps-install-briefing-pipeline.ps1"

& "C:\jcm\scripts\vps-ensure-forward-bot.ps1"

Write-Host "--- POST-DEPLOY STATUS ---"
$f = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'loader\.mjs.*run-forward-demo-30d' }).Count
$w = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'loader\.mjs.*watchdog\.ts' }).Count
Write-Host "Forward leaf workers: $f"
Write-Host "Watchdog leaf workers: $w"
if (Test-Path "C:\logs\jcm\daily-briefing-telegram.log") {
    Get-Content "C:\logs\jcm\daily-briefing-telegram.log" -Tail 5
}
'@

$tmp = Join-Path $env:TEMP "vps-deploy-production-stack-remote.ps1"
Set-Content -Path $tmp -Value $remotePs1 -Encoding UTF8
scp $tmp "${HostName}:C:/Users/Administrator/vps-deploy-production-stack-remote.ps1"
ssh $HostName "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-deploy-production-stack-remote.ps1"

Write-Host "=== Production stack deploy complete ===" -ForegroundColor Green
