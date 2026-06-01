# Deploy MT5 rejection fixes to VPS (infra only — no strategy changes).
# Run locally: powershell -File scripts\vps-deploy-rejection-fix.ps1
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Jcm = "C:/Users/Administrator/Documents/JCM agents/JCM-agents"
$Bilshenz = "C:/opt/bilshenz"
$HostName = if ($env:VPS_HOST) { $env:VPS_HOST } else { "jcm-vps" }

$files = @(
    @{ Local = "$Root\infra\bilshenz\run-forward-demo-30d.ts"; Remote = "$Jcm/infra/bilshenz/run-forward-demo-30d.ts" },
    @{ Local = "$Root\infra\bilshenz\broker\executeBrokerRoutes.ts"; Remote = "$Jcm/infra/bilshenz/broker/executeBrokerRoutes.ts" },
    @{ Local = "$Root\infra\bilshenz\broker\mt5PythonApi.ts"; Remote = "$Jcm/infra/bilshenz/broker/mt5PythonApi.ts" },
    @{ Local = "$Root\infra\bilshenz\mt5\mt5_connector.py"; Remote = "$Jcm/infra/bilshenz/mt5/mt5_connector.py" },
    @{ Local = "$Root\watchdog.vps.ts"; Remote = "$Jcm/watchdog.vps.ts" },
    @{ Local = "$Root\start-all-now.vps.ps1"; Remote = "$Jcm/start-all-now.vps.ps1" },
    @{ Local = "$Root\scripts\vps-ensure-forward-bot.ps1"; Remote = "$Jcm/scripts/vps-ensure-forward-bot.ps1" },
    @{ Local = "$Root\scripts\vps-forward-preflight.ps1"; Remote = "$Jcm/scripts/vps-forward-preflight.ps1" }
)

Write-Host "=== Deploy rejection fixes to $HostName ===" -ForegroundColor Cyan
$direct = @(
    @{ Local = "$Root\infra\bilshenz\run-forward-demo-30d.ts"; Remote = "$Bilshenz/backend/scripts/run-forward-demo-30d.ts" },
    @{ Local = "$Root\infra\bilshenz\broker\executeBrokerRoutes.ts"; Remote = "$Bilshenz/backend/broker/executeBrokerRoutes.ts" },
    @{ Local = "$Root\infra\bilshenz\broker\mt5PythonApi.ts"; Remote = "$Bilshenz/backend/broker/mt5PythonApi.ts" },
    @{ Local = "$Root\infra\bilshenz\mt5\mt5_connector.py"; Remote = "$Bilshenz/mt5_trading_system/python/mt5_connector.py" },
    @{ Local = "$Root\watchdog.vps.ts"; Remote = "$Bilshenz/deploy/watchdog.ts" }
)
foreach ($f in $direct) {
    if (-not (Test-Path $f.Local)) { throw "Missing local file: $($f.Local)" }
    Write-Host "  scp -> $($f.Remote)"
    scp $f.Local "${HostName}:$($f.Remote)"
}

foreach ($f in $files) {
    if (-not (Test-Path $f.Local)) { continue }
    $dir = ($f.Remote -replace '/[^/]+$','')
    ssh $HostName "powershell -NoProfile -Command \"New-Item -ItemType Directory -Force -Path '$dir' | Out-Null\"" 2>$null
    scp $f.Local "${HostName}:$($f.Remote)" 2>$null
}

$remotePs1 = @'
$B = "C:\opt\bilshenz"
Write-Host "Bilshenz rejection-fix files installed (direct scp)"
schtasks /End /TN Bilshenz-ForwardBot-Sys 2>$null
schtasks /End /TN Bilshenz-MT5-API-Sys 2>$null
Start-Sleep 5
$term = if ($env:MT5_TERMINAL_PATH) { $env:MT5_TERMINAL_PATH } else { "C:\Program Files\MetaTrader 5 Exness" }
$exe = Join-Path $term "terminal64.exe"
if ((Test-Path $exe) -and -not (Get-Process terminal64 -EA SilentlyContinue)) {
  Start-Process $exe -ArgumentList "/algotrading"
  Start-Sleep 45
}
schtasks /Run /TN Bilshenz-MT5-API-Sys 2>$null
Start-Sleep 15
schtasks /Run /TN Bilshenz-ForwardBot-Sys 2>$null
Start-Sleep 10
$st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
Write-Host "MT5 connected:" $st.connected "terminal_trade:" $st.terminal_trade_allowed
'@

$tmpRemote = Join-Path $env:TEMP "vps-deploy-rejection-fix-remote.ps1"
Set-Content -Path $tmpRemote -Value $remotePs1 -Encoding UTF8
scp $tmpRemote "${HostName}:C:/Users/Administrator/deploy-rejection-fix-remote.ps1"
ssh $HostName "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\deploy-rejection-fix-remote.ps1"

Write-Host "=== Deploy complete ===" -ForegroundColor Green
