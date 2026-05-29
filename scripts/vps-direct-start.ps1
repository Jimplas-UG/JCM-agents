# Direct detached startup - works over SSH (no interactive scheduled task needed)
$ErrorActionPreference = "Continue"
$AppDir = "C:\opt\bilshenz"
$Win = Join-Path $AppDir "deploy\windows"
$LogDir = "C:\logs\tradingbot"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" -ForegroundColor Cyan }
function PortUp([int]$p) { return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }

Log "=== DIRECT START (trading stack) ==="

# Load Bilshenz env
. (Join-Path $Win "Import-TradingBotEnv.ps1")

# DB + Redis for JCM
foreach ($svc in @("postgresql-x64-17", "Memurai")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Start-Service $svc; Log "Started $svc" }
}

# MT5 terminal
$mt5Path = if ($env:MT5_TERMINAL_PATH) { $env:MT5_TERMINAL_PATH } else { "C:\Program Files\MetaTrader 5 Exness" }
$term = Join-Path $mt5Path "terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -ErrorAction SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"
    Log "Started MT5 terminal"
    Start-Sleep -Seconds 25
}

# MT5 API :8765
if (-not (PortUp 8765)) {
    $PyDir = Join-Path $AppDir "mt5_trading_system\python"
    $py = Join-Path $PyDir ".venv\Scripts\python.exe"
    $env:PORT = "8765"
    $env:MT5_TERMINAL_PATH = $mt5Path
    Start-Process -FilePath $py -ArgumentList "main.py" -WorkingDirectory $PyDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $LogDir "mt5-api.log") `
        -RedirectStandardError (Join-Path $LogDir "mt5-api.err.log")
    Log "Started MT5 API (python main.py)"
    Start-Sleep -Seconds 15
}

# Desk API :8791
if (-not (PortUp 8791)) {
    $backend = Join-Path $AppDir "backend"
    $env:STRATEGY_FREEZE = "1"
    $env:DESK_API_PORT = "8791"
    $npx = (Get-Command npx.cmd -ErrorAction SilentlyContinue).Source
    if (-not $npx) { $npx = "npx.cmd" }
    Start-Process -FilePath $npx -ArgumentList "tsx", "src/server.ts" -WorkingDirectory $backend `
        -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $LogDir "desk-api.log") `
        -RedirectStandardError (Join-Path $LogDir "desk-api.err.log")
    Log "Started Desk API"
    Start-Sleep -Seconds 12
}

# Forward bot
& (Join-Path $Win "run-forward-bot.ps1") -AppDir $AppDir
Start-Sleep -Seconds 10

# Bilshenz watchdog - disabled during recovery (was causing restart loops)
# Start manually only after MT5+desk+forward stable for 30+ minutes
# $wdRunning = Get-CimInstance Win32_Process ...
Log "Skipped Bilshenz watchdog (prevent restart loop)"

# JCM platform
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
if (Test-Path "$Jcm\scripts\start-platform.ps1") {
    & "$Jcm\scripts\start-platform.ps1"
}
if (Test-Path "C:\Users\Administrator\start-sidecars.ps1") {
    & "C:\Users\Administrator\start-sidecars.ps1"
}
if (-not (PortUp 3000) -and (Test-Path "C:\Users\Administrator\vps-start-dashboard.ps1")) {
    & "C:\Users\Administrator\vps-start-dashboard.ps1"
}

Start-Sleep -Seconds 10
Log "--- STATUS ---"
foreach ($p in 8765,8791,8000,3000,8083,8084) {
    Log ":$p $(if (PortUp $p) { 'UP' } else { 'DOWN' })"
}
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 8
    Log "MT5 connected=$($m.connected) trade_allowed=$($m.trade_allowed)"
} catch { Log "MT5 health pending" }
try {
    $h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 8
    Log "JCM $($h.status) db=$($h.database)"
} catch { Log "JCM API pending" }
if (Test-Path "C:\logs\tradingbot\forward-bot.err.log") {
    Get-Content "C:\logs\tradingbot\forward-bot.err.log" -Tail 3 | ForEach-Object { Log "forward: $_" }
}
Log "=== DONE ==="
