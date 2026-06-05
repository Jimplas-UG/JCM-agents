$ErrorActionPreference = "Continue"
Write-Host "=== VPS forward alignment verify ==="

$st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
Write-Host "MT5 connected=$($st.connected) trade_allowed=$($st.terminal_trade_allowed)"

try {
    $rc = Invoke-RestMethod "http://127.0.0.1:8765/api/reconnect" -Method POST -TimeoutSec 15
    Write-Host "reconnect ok=$($rc.ok)"
} catch {
    Write-Host "reconnect: $($_.Exception.Message)"
}

$fwd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "run-forward-demo"
})
Write-Host "forward_processes=$($fwd.Count)"
foreach ($p in $fwd) {
    Write-Host "  PID $($p.ProcessId)"
}

$log = "C:\logs\tradingbot\forward-demo.log"
if (Test-Path $log) {
    Write-Host "--- forward log tail ---"
    Get-Content $log -Tail 8
}

try {
    $trades = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/trades?limit=10" -TimeoutSec 10
    $open = @($trades | Where-Object { $_.outcome -eq "open" })
    $closed = @($trades | Where-Object { $_.outcome -ne "open" })
    Write-Host "JCM trades open=$($open.Count) closed=$($closed.Count)"
} catch {
    Write-Host "JCM trades: $($_.Exception.Message)"
}

Write-Host "=== done ==="
