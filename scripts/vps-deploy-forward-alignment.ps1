# Deploy forward-alignment fixes (execution + observability only — BSv3.2 unchanged).
# Run locally: powershell -File scripts\vps-deploy-forward-alignment.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$HostName = if ($env:VPS_HOST) { $env:VPS_HOST } else { "jcm-vps" }
$Jcm = "C:/jcm-project"
$Bilshenz = "C:/opt/bilshenz"

Write-Host "=== Deploy forward alignment to $HostName ===" -ForegroundColor Cyan

$direct = @(
    @{ Local = "$Root\infra\bilshenz\run-forward-demo-30d.ts"; Remote = "$Bilshenz/backend/scripts/run-forward-demo-30d.ts" },
    @{ Local = "$Root\infra\bilshenz\jcm\jcmPositionWatcher.ts"; Remote = "$Bilshenz/backend/jcm/jcmPositionWatcher.ts" },
    @{ Local = "$Root\infra\bilshenz\jcm\jcmSupervisorPublisher.ts"; Remote = "$Bilshenz/backend/jcm/jcmSupervisorPublisher.ts" },
    @{ Local = "$Root\infra\bilshenz\broker\mt5PythonApi.ts"; Remote = "$Bilshenz/backend/broker/mt5PythonApi.ts" },
    @{ Local = "$Root\infra\bilshenz\mt5\mt5_connector.py"; Remote = "$Bilshenz/mt5_trading_system/python/mt5_connector.py" },
    @{ Local = "$Root\infra\bilshenz\mt5\main.py"; Remote = "$Bilshenz/mt5_trading_system/python/main.py" },
    @{ Local = "$Root\backend\app\scripts\backfill_trade_closed_from_mt5.py"; Remote = "$Jcm/backend/app/scripts/backfill_trade_closed_from_mt5.py" },
    @{ Local = "$Root\scripts\vps-ensure-forward-bot.ps1"; Remote = "$Jcm/scripts/vps-ensure-forward-bot.ps1" },
    @{ Local = "$Root\scripts\vps-backfill-trade-closed.ps1"; Remote = "$Jcm/scripts/vps-backfill-trade-closed.ps1" },
    @{ Local = "$Root\scripts\vps-install-execution-ensure-task.ps1"; Remote = "$Jcm/scripts/vps-install-execution-ensure-task.ps1" }
)

foreach ($f in $direct) {
    if (-not (Test-Path $f.Local)) { throw "Missing $($f.Local)" }
    Write-Host "  scp -> $($f.Remote)"
    scp $f.Local "${HostName}:$($f.Remote)"
}

$remotePs1 = @'
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path "C:\jcm\scripts" | Out-Null
New-Item -ItemType Directory -Force -Path "C:\jcm-project\backend\app\scripts" | Out-Null
$vj = "C:\opt\bilshenz\backend\scripts\validation"
$vt = "C:\opt\bilshenz\backend\validation"
if (-not (Test-Path $vj)) {
  cmd /c mklink /J "$vj" "$vt" 2>$null
}
Copy-Item "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1" "C:\jcm\scripts\" -Force -EA SilentlyContinue

$term = if ($env:MT5_TERMINAL_PATH) { $env:MT5_TERMINAL_PATH } else { "C:\Program Files\MetaTrader 5 Exness" }
$exe = Join-Path $term "terminal64.exe"
if ((Test-Path $exe) -and -not (Get-Process terminal64 -EA SilentlyContinue)) {
  Start-Process $exe -ArgumentList "/algotrading"
  Start-Sleep 45
}

foreach ($tn in @("Bilshenz-MT5-API-Sys","Bilshenz-MT5-API")) {
  schtasks /Query /TN $tn 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { schtasks /Run /TN $tn 2>$null; break }
}
Start-Sleep 15
try { Invoke-RestMethod "http://127.0.0.1:8765/api/reconnect" -Method POST -TimeoutSec 20 | Out-Null } catch {}

$fwdLauncher = "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
if (Test-Path $fwdLauncher) {
  $raw = Get-Content $fwdLauncher -Raw
  $raw = $raw -replace 'scripts/scripts/run-forward-demo-30d\.ts', 'scripts/run-forward-demo-30d.ts'
  if ($raw -notmatch 'scripts/run-forward-demo-30d\.ts') {
    $raw = $raw -replace '(?<!scripts/)run-forward-demo-30d\.ts', 'scripts/run-forward-demo-30d.ts'
  }
  Set-Content $fwdLauncher $raw -Encoding UTF8
}
foreach ($tn in @("Bilshenz-ForwardBot-Sys","Bilshenz-ForwardBot")) {
  schtasks /Query /TN $tn 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) { schtasks /End /TN $tn 2>$null; Start-Sleep 3; schtasks /Run /TN $tn 2>$null; break }
}
Start-Sleep 12

& "C:\jcm-project\scripts\vps-install-execution-ensure-task.ps1"
& "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1"

$st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
Write-Host "MT5 connected:" $st.connected "trade_allowed:" $st.terminal_trade_allowed
try {
  & "C:\jcm-project\scripts\vps-backfill-trade-closed.ps1"
} catch { Write-Host "Backfill skipped:" $_.Exception.Message }
'@

$tmpRemote = Join-Path $env:TEMP "vps-deploy-forward-alignment-remote.ps1"
Set-Content -Path $tmpRemote -Value $remotePs1 -Encoding UTF8
scp $tmpRemote "${HostName}:C:/Users/Administrator/deploy-forward-alignment-remote.ps1"
ssh $HostName "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\deploy-forward-alignment-remote.ps1"

Write-Host "=== Forward alignment deploy complete ===" -ForegroundColor Green
