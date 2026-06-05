$ErrorActionPreference = "Continue"
schtasks /End /TN Bilshenz-MT5-API-Sys 2>$null
Start-Sleep -Seconds 5
schtasks /Run /TN Bilshenz-MT5-API-Sys 2>$null
Start-Sleep -Seconds 20
try {
    $r = Invoke-RestMethod "http://127.0.0.1:8765/api/reconnect" -Method POST -TimeoutSec 15
    Write-Host "reconnect ok=$($r.ok)"
} catch {
    Write-Host "reconnect err: $($_.Exception.Message)"
}
$st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
Write-Host "connected=$($st.connected) trade=$($st.terminal_trade_allowed)"
schtasks /End /TN Bilshenz-ForwardBot-Sys 2>$null
Start-Sleep -Seconds 3
schtasks /Run /TN Bilshenz-ForwardBot-Sys 2>$null
Start-Sleep -Seconds 15
$fwd = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "run-forward-demo" }
Write-Host "forward_count=$($fwd.Count)"
& "C:\jcm-project\scripts\vps-backfill-trade-closed.ps1"
