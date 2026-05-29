Set-Location "C:\opt\bilshenz\mt5_trading_system\python"
$env:PORT = "8765"
$env:MT5_TERMINAL_PATH = "C:\Program Files\MetaTrader 5 Exness"
Write-Host "Starting MT5 main.py (15s)..."
$job = Start-Job { Set-Location "C:\opt\bilshenz\mt5_trading_system\python"; $env:PORT="8765"; & ".\.venv\Scripts\python.exe" main.py 2>&1 }
Start-Sleep -Seconds 15
Receive-Job $job
$p = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue
Write-Host "Port 8765: $(if($p){'UP'}else{'DOWN'})"
Stop-Job $job -EA SilentlyContinue; Remove-Job $job -EA SilentlyContinue
