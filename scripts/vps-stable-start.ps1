# Detached start - processes survive SSH disconnect and scheduled task exit
$ErrorActionPreference = "Continue"
. "C:\opt\bilshenz\deploy\windows\Import-TradingBotEnv.ps1"
$LogDir = "C:\logs\tradingbot"
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
New-Item -ItemType Directory -Force -Path $LogDir, "$Jcm\backend\logs" | Out-Null

function PortUp([int]$p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }
function Log($m) { Write-Host "[$(Get-Date -Format HH:mm:ss)] $m" }
function Start-Detached([string]$name, [string]$exe, [string]$args, [string]$wd) {
    $cmd = "cd /d `"$wd`" && start `"$name`" /MIN `"$exe`" $args"
    Start-Process cmd.exe -ArgumentList "/c", $cmd -WindowStyle Hidden
    Log "Detached start: $name"
}

Log "=== DETACHED START ==="

foreach ($svc in @("postgresql-x64-17","Memurai")) {
    $s = Get-Service $svc -EA SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Start-Service $svc }
}

$term = "C:\Program Files\MetaTrader 5 Exness\terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -EA SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"; Start-Sleep 20
    Log "MT5 terminal started"
}

if (-not (PortUp 8765)) {
    $PyDir = "C:\opt\bilshenz\mt5_trading_system\python"
    $py = Join-Path $PyDir ".venv\Scripts\python.exe"
    Start-Detached "MT5API" $py "main.py" $PyDir
    Start-Sleep 18
}

if (-not (PortUp 8791)) {
    $backend = "C:\opt\bilshenz\backend"
    $node = (Get-Command node.exe).Source
    $tsx = Join-Path $backend "node_modules\tsx\dist\cli.mjs"
    Start-Detached "DeskAPI" $node "`"$tsx`" src/server.ts" $backend
    Start-Sleep 12
}

if (-not (PortUp 8000)) {
    $be = Join-Path $Jcm "backend"
    $py = Join-Path $be ".venv\Scripts\python.exe"
    Copy-Item (Join-Path $Jcm ".env") (Join-Path $be ".env") -Force -EA SilentlyContinue
    Start-Detached "JCMAPI" $py "-m uvicorn app.main:app --host 0.0.0.0 --port 8000" $be
    Start-Sleep 10
}

if (-not (PortUp 8083)) {
    $sidecar = Join-Path $Jcm "infra\bot-integration"
    $py = Join-Path $Jcm "backend\.venv\Scripts\python.exe"
    Start-Detached "SidecarFwd" $py "stub_execution_layer.py forward" $sidecar
    Start-Detached "SidecarWD" $py "stub_execution_layer.py watchdog" $sidecar
    Start-Sleep 6
}

if (-not (PortUp 3000)) {
    $standalone = Join-Path $Jcm "frontend\.next\standalone"
    $staticSrc = Join-Path $Jcm "frontend\.next\static"
    $staticDst = Join-Path $standalone ".next\static"
    if (Test-Path $staticSrc) {
        New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
        Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
    }
    $node = (Get-Command node.exe).Source
    Start-Detached "Dashboard" $node "server.js" $standalone
    Start-Sleep 8
}

& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"

foreach ($rule in @(
    @{Name="JCM-Dashboard-3000"; Port=3000},
    @{Name="JCM-API-8000"; Port=8000}
)) {
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $rule.Port | Out-Null
    }
}

Log "=== DETACHED START DONE ==="
