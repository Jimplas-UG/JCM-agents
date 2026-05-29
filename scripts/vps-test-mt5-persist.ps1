# Test: start MT5 API with cmd start /MIN and verify it stays up 30s
$py = "C:\opt\bilshenz\mt5_trading_system\python\.venv\Scripts\python.exe"
$PyDir = "C:\opt\bilshenz\mt5_trading_system\python"
$env:PORT = "8765"
$env:MT5_TERMINAL_PATH = "C:\Program Files\MetaTrader 5 Exness"
Set-Location $PyDir
Start-Process cmd.exe -ArgumentList "/c","start","/MIN","MT5API","`"$py`"","main.py" -WindowStyle Hidden
Write-Host "Started MT5 via cmd start"
1..6 | ForEach-Object {
    Start-Sleep -Seconds 5
    $l = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue
    Write-Host "t+${_}0s :8765 $(if($l){'UP pid='+$l.OwningProcess}else{'DOWN'})"
}
