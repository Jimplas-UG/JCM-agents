# Finish recovery: MT5 API + forward + JCM (safe, no watchdog)
$ErrorActionPreference = "Continue"
. "C:\opt\bilshenz\deploy\windows\Import-TradingBotEnv.ps1"
$LogDir = "C:\logs\tradingbot"
function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }

# Disable Bilshenz watchdog task (was killing stack in restart loops)
schtasks /Change /TN "Bilshenz-Watchdog" /DISABLE 2>$null
Write-Host "Disabled Bilshenz-Watchdog scheduled task"

if (-not (PortUp 8765)) {
    $PyDir = "C:\opt\bilshenz\mt5_trading_system\python"
    $env:PORT = "8765"
    $env:MT5_TERMINAL_PATH = "C:\Program Files\MetaTrader 5 Exness"
    Start-Process "$PyDir\.venv\Scripts\python.exe" -ArgumentList "main.py" -WorkingDirectory $PyDir -WindowStyle Hidden
    Write-Host "Started MT5 API"
    Start-Sleep -Seconds 20
}

& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
Start-Sleep -Seconds 12

foreach ($svc in @("postgresql-x64-17","Memurai")) {
    $s = Get-Service $svc -EA SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Start-Service $svc }
}

$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
& "$Jcm\scripts\start-platform.ps1"
& "C:\Users\Administrator\start-sidecars.ps1"
& "C:\Users\Administrator\vps-start-dashboard.ps1"

Start-Sleep -Seconds 10
& "C:\Users\Administrator\vps-process-check.ps1"
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 8
    Write-Host "MT5 connected=$($m.connected)"
} catch {}
Get-Content "$LogDir\forward-bot.err.log" -Tail 4 -ErrorAction SilentlyContinue
