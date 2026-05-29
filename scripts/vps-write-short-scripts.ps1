# Short-path launchers (no spaces) - copy to C:\jcm\
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
New-Item -ItemType Directory -Force -Path C:\jcm | Out-Null

@'
Set-Location "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone"
$env:PORT = "3000"
$env:HOSTNAME = "0.0.0.0"
$staticSrc = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\static"
$staticDst = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone\.next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}
& "C:\Program Files\nodejs\node.exe" server.js
'@ | Set-Content C:\jcm\run-dashboard.ps1 -Encoding UTF8

@'
Set-Location "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend"
Copy-Item "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env" .env -Force -EA SilentlyContinue
& "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\.venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
'@ | Set-Content C:\jcm\run-api.ps1 -Encoding UTF8

@'
. "C:\opt\bilshenz\deploy\windows\Import-TradingBotEnv.ps1"
$mt5Path = "C:\Program Files\MetaTrader 5 Exness"
$term = Join-Path $mt5Path "terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -ErrorAction SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"
    Start-Sleep -Seconds 30
}
Set-Location "C:\opt\bilshenz\mt5_trading_system\python"
$env:PORT = "8765"
$env:MT5_TERMINAL_PATH = $mt5Path
& "C:\opt\bilshenz\mt5_trading_system\python\.venv\Scripts\python.exe" main.py
'@ | Set-Content C:\jcm\run-mt5.ps1 -Encoding UTF8

@'
$here = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\infra\bot-integration"
$py = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\.venv\Scripts\python.exe"
Start-Process $py -ArgumentList "stub_execution_layer.py","forward" -WorkingDirectory $here -WindowStyle Hidden
Start-Process $py -ArgumentList "stub_execution_layer.py","watchdog" -WorkingDirectory $here -WindowStyle Hidden
while ($true) { Start-Sleep 3600 }
'@ | Set-Content C:\jcm\run-sidecars.ps1 -Encoding UTF8

Write-Host "Scripts written to C:\jcm\"
