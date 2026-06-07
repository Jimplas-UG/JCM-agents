$ErrorActionPreference = "Continue"
Write-Host "=== FORWARD + WATCHDOG DIAG $(Get-Date -Format 'yyyy-MM-dd HH:mm') ==="

foreach ($tn in @("Bilshenz-ForwardBot-Sys","Bilshenz-ForwardBot","Bilshenz-Watchdog","Bilshenz-Watchdog-Sys","JCM-Execution-Stack-Ensure")) {
    schtasks /Query /TN $tn /FO LIST 2>$null | Select-String "TaskName|Status|Last Result|Last Run"
    Write-Host ""
}

Write-Host "--- Ports ---"
foreach ($p in @(8765,8791,8083,8084)) {
    $c = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    Write-Host "Port $p : $(if ($c) { 'LISTEN' } else { 'DOWN' })"
}

Write-Host "--- Forward processes ---"
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo'
} | ForEach-Object { Write-Host "PID $($_.ProcessId): $($_.CommandLine.Substring(0, [Math]::Min(200, $_.CommandLine.Length)))" }

$errLog = "C:\logs\tradingbot\forward-bot.err.log"
if (Test-Path $errLog) {
    Write-Host "--- forward-bot.err.log (tail 15) ---"
    Get-Content $errLog -Tail 15
}

$wdLog = "C:\logs\tradingbot\watchdog.log"
if (Test-Path $wdLog) {
    Write-Host "--- watchdog.log (tail 15) ---"
    Get-Content $wdLog -Tail 15
}

try {
    $st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 8
    Write-Host "MT5 connected=$($st.connected) autotrading=$($st.terminal_trade_allowed)"
} catch { Write-Host "MT5 status FAIL: $($_.Exception.Message)" }
