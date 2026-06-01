# Forward-demo execution preflight — MT5 must be connected + algo trading enabled.
# Run on VPS: powershell -File C:\jcm-project\scripts\vps-forward-preflight.ps1
$ErrorActionPreference = "Continue"
$mt5 = "http://127.0.0.1:8765/api/status"
$desk = "http://127.0.0.1:8791/health"

Write-Host "=== Forward demo preflight ===" -ForegroundColor Cyan
try {
    $s = Invoke-RestMethod $mt5 -TimeoutSec 10
    Write-Host "MT5 connected:" $s.connected
    Write-Host "Terminal trade allowed:" $s.terminal_trade_allowed
    Write-Host "Account trade allowed:" $s.account.trade_allowed
    Write-Host "Server:" $s.account.server "Equity:" $s.account.equity
    if (-not $s.connected) { Write-Host "FAIL: MT5 API not connected" -ForegroundColor Red }
    if (-not $s.terminal_trade_allowed) {
        Write-Host "FAIL: Enable Algo Trading in MT5 (toolbar) — causes retcode 10027" -ForegroundColor Red
    }
    if (-not $s.account.trade_allowed) {
        Write-Host "WARN: Account trade_allowed=false" -ForegroundColor Yellow
    }
} catch {
    Write-Host "FAIL: MT5 API unreachable at $mt5" -ForegroundColor Red
    Write-Host $_.Exception.Message
}

try {
    $d = Invoke-RestMethod $desk -TimeoutSec 5
    Write-Host "Desk API:" ($d.status ?? "ok")
} catch {
    Write-Host "WARN: Desk API not reachable" -ForegroundColor Yellow
}

$fwd = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq "node.exe" -and $_.CommandLine -match "run-forward-demo-30d"
}
if ($fwd) { Write-Host "Forward bot: RUNNING (pid $($fwd.ProcessId))" -ForegroundColor Green }
else { Write-Host "Forward bot: NOT RUNNING" -ForegroundColor Yellow }
