# Fix forward bot + Bilshenz watchdog launchers (infra only).
# Run locally: powershell -File scripts\vps-deploy-forward-watchdog-fix.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$HostName = if ($env:VPS_HOST) { $env:VPS_HOST } else { "jcm-vps" }
$Jcm = "C:/jcm-project"
$Bilshenz = "C:/opt/bilshenz"

Write-Host "=== Deploy forward + watchdog fix to $HostName ===" -ForegroundColor Cyan

$files = @(
    @{ Local = "$Root\run-forward-bot.vps.ps1"; Remote = "$Jcm/run-forward-bot.vps.ps1" },
    @{ Local = "$Root\run-watchdog.vps.ps1"; Remote = "$Jcm/run-watchdog.vps.ps1" },
    @{ Local = "$Root\watchdog.vps.ts"; Remote = "$Jcm/watchdog.vps.ts" },
    @{ Local = "$Root\watchdog.vps.ts"; Remote = "$Bilshenz/deploy/watchdog.ts" },
    @{ Local = "$Root\scripts\vps-ensure-forward-bot.ps1"; Remote = "$Jcm/scripts/vps-ensure-forward-bot.ps1" }
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
Copy-Item "C:\jcm-project\watchdog.vps.ts" "C:\opt\bilshenz\deploy\watchdog.ts" -Force
Copy-Item "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1" "C:\jcm\scripts\" -Force -EA SilentlyContinue

Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.Name -eq 'node.exe' -and ($_.CommandLine -match 'run-forward-demo-30d|watchdog\.ts')
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 5

& "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1"

$fwd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.CommandLine -match 'run-forward-demo-30d'
})
$wd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
  $_.CommandLine -match 'watchdog\.ts'
})
Write-Host "Forward workers:" $fwd.Count
Write-Host "Watchdog workers:" $wd.Count
if (Test-Path "C:\logs\tradingbot\forward-bot.err.log") {
  Get-Content "C:\logs\tradingbot\forward-bot.err.log" -Tail 5
}
if (Test-Path "C:\logs\tradingbot\watchdog.log") {
  Get-Content "C:\logs\tradingbot\watchdog.log" -Tail 5
}
'@

$tmpRemote = Join-Path $env:TEMP "vps-deploy-forward-watchdog-fix-remote.ps1"
Set-Content -Path $tmpRemote -Value $remotePs1 -Encoding UTF8
scp $tmpRemote "${HostName}:C:/Users/Administrator/deploy-forward-watchdog-fix-remote.ps1"
ssh $HostName "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\deploy-forward-watchdog-fix-remote.ps1"

Write-Host "=== Forward + watchdog fix deploy complete ===" -ForegroundColor Green
