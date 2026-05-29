# Emergency full stack recovery (trading first, then JCM observability)
$ErrorActionPreference = "Continue"
$Log = "C:\Users\Administrator\emergency-up.log"
function Log($m) { $l="[$(Get-Date -Format HH:mm:ss)] $m"; Write-Host $l -ForegroundColor Cyan; Add-Content $Log $l }

Log "=== EMERGENCY STACK RECOVERY ==="

foreach ($svc in @("postgresql-x64-17", "Memurai")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Start-Service $svc; Log "Started $svc" }
}

$mt5Path = "C:\Program Files\MetaTrader 5 Exness\terminal64.exe"
if ((Test-Path $mt5Path) -and -not (Get-Process terminal64 -ErrorAction SilentlyContinue)) {
    Start-Process $mt5Path -ArgumentList "/algotrading"
    Log "Started MT5 terminal"
    Start-Sleep -Seconds 20
}

foreach ($tn in @("Bilshenz-MT5-API", "Bilshenz-DeskAPI", "Bilshenz-ForwardBot", "Bilshenz-Watchdog")) {
    Log "Running task $tn"
    schtasks /Run /TN $tn 2>&1 | Out-Null
    Start-Sleep -Seconds 5
}

Log "Waiting 45s for Bilshenz ports..."
Start-Sleep -Seconds 45

function PortUp($p) { return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }

if (-not (PortUp 8765)) {
    Log "MT5 still down - retry Bilshenz-MT5-API"
    schtasks /Run /TN "Bilshenz-MT5-API" 2>&1 | Out-Null
    Start-Sleep -Seconds 20
}
if (-not (PortUp 8791)) {
    Log "Desk still down - retry Bilshenz-DeskAPI"
    schtasks /Run /TN "Bilshenz-DeskAPI" 2>&1 | Out-Null
    Start-Sleep -Seconds 15
}

# Forward bot direct start if task did not spawn worker
$errLog = "C:\logs\tradingbot\forward-bot.err.log"
$fwdFresh = $false
if (Test-Path $errLog) {
    $fi = Get-Item $errLog
    if ($fi.Length -gt 0 -and ((Get-Date) - $fi.LastWriteTime).TotalMinutes -lt 3) { $fwdFresh = $true }
}
if (-not $fwdFresh) {
    Log "Starting forward bot via run-forward-bot.ps1"
    & "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -AppDir "C:\opt\bilshenz"
    Start-Sleep -Seconds 15
}

# JCM supervisory layer
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
if (Test-Path "$Jcm\scripts\start-platform.ps1") {
    Log "Starting JCM platform"
    & "$Jcm\scripts\start-platform.ps1" 2>&1 | ForEach-Object { Log $_ }
}
if (Test-Path "C:\Users\Administrator\start-sidecars.ps1") {
    & "C:\Users\Administrator\start-sidecars.ps1" 2>&1 | ForEach-Object { Log $_ }
}
if (-not (PortUp 3000) -and (Test-Path "C:\Users\Administrator\vps-start-dashboard.ps1")) {
    & "C:\Users\Administrator\vps-start-dashboard.ps1" 2>&1 | ForEach-Object { Log $_ }
}

Log "--- STATUS ---"
foreach ($p in 8765,8791,8000,3000,8083,8084) {
    Log ":$p $(if (PortUp $p) { 'UP' } else { 'DOWN' })"
}
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 8
    Log "MT5 connected=$($m.connected)"
} catch { Log "MT5 API not responding yet" }
try {
    $h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 8
    Log "JCM API $($h.status)"
} catch { Log "JCM API not responding yet" }
Log "=== RECOVERY COMPLETE ==="
