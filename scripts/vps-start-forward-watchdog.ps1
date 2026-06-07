# Start forward + watchdog — dedupe first (run ON VPS)
$ErrorActionPreference = "Continue"
$App = "C:\opt\bilshenz"
. "C:\jcm-project\scripts\vps-tsx-worker.ps1"

Stop-TsxWorkerAll 'run-forward-demo-30d'
Stop-TsxWorkerAll 'watchdog\.ts'
Start-Sleep 4

Copy-Item "C:\jcm-project\watchdog.vps.ts" "$App\deploy\watchdog.ts" -Force -EA SilentlyContinue
Copy-Item "C:\jcm-project\run-forward-bot.vps.ps1" "$App\deploy\windows\run-forward-bot.ps1" -Force
Copy-Item "C:\jcm-project\run-watchdog.vps.ps1" "$App\deploy\windows\run-watchdog.ps1" -Force
Copy-Item "C:\jcm-project\scripts\vps-tsx-worker.ps1" "$App\deploy\windows\vps-tsx-worker.ps1" -Force

& "$App\deploy\windows\run-forward-bot.ps1" -AppDir $App
Start-Sleep 10
& "$App\deploy\windows\run-watchdog.ps1" -AppDir $App
Start-Sleep 8

Write-Host "Forward leaf: $(Test-TsxWorkerRunning 'run-forward-demo-30d') PIDs: $(Get-TsxWorkerNodeCount 'run-forward-demo-30d')"
Write-Host "Watchdog leaf: $(Test-TsxWorkerRunning 'watchdog\.ts') PIDs: $(Get-TsxWorkerNodeCount 'watchdog\.ts')"
