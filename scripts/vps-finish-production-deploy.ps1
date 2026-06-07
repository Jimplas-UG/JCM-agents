# Run ON VPS after scp — finish install + ensure + test
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path "C:\jcm\scripts" | Out-Null
Copy-Item "C:\jcm-project\run-forward-bot.vps.ps1" "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -Force
Copy-Item "C:\jcm-project\run-watchdog.vps.ps1" "C:\opt\bilshenz\deploy\windows\run-watchdog.ps1" -Force
Copy-Item "C:\jcm-project\scripts\vps-tsx-worker.ps1" "C:\opt\bilshenz\deploy\windows\vps-tsx-worker.ps1" -Force
Copy-Item "C:\jcm-project\watchdog.vps.ts" "C:\opt\bilshenz\deploy\watchdog.ts" -Force
Copy-Item "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1" "C:\jcm\scripts\" -Force
Copy-Item "C:\jcm-project\scripts\vps-tsx-worker.ps1" "C:\jcm\scripts\" -Force
Copy-Item "C:\jcm-project\scripts\vps-install-execution-ensure-task.ps1" "C:\jcm\scripts\" -Force

& "C:\jcm\scripts\vps-install-execution-ensure-task.ps1"
& "C:\jcm-project\scripts\vps-install-briefing-pipeline.ps1"

Write-Host "Running ensure (forward + watchdog + briefing)..."
& "C:\jcm\scripts\vps-ensure-forward-bot.ps1"

Write-Host "--- STATUS ---"
$f = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'loader\.mjs.*run-forward-demo-30d' }).Count
$w = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'loader\.mjs.*watchdog\.ts' }).Count
Write-Host "Forward leaf: $f  Watchdog leaf: $w"
Get-Content "C:\logs\tradingbot\forward-bot.err.log" -Tail 2 -EA SilentlyContinue
Get-Content "C:\logs\jcm\daily-briefing-telegram.log" -Tail 5 -EA SilentlyContinue
