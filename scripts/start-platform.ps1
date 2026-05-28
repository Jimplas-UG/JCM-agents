# JCM BSv3.2 Platform - start all services on this VPS
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"
$BotIntegration = Join-Path $Root "infra\bot-integration"
$Python = Join-Path $Backend ".venv\Scripts\python.exe"
$Npm = (Get-Command npm -ErrorAction SilentlyContinue).Source

function Test-PortListen($port) {
    return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

Write-Host "=== JCM Platform Startup ===" -ForegroundColor Cyan

# Windows services
foreach ($svc in @("postgresql-x64-17", "Memurai")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Running") {
        Start-Service $svc
        Write-Host "Started service: $svc"
    }
}

# Sync env
Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force
Copy-Item (Join-Path $Root ".env") (Join-Path $Frontend ".env.local") -Force

# JCM sidecars for forward-bot + watchdog health (8083-8084); MT5/desk are Bilshenz :8765/:8791
if (-not (Test-PortListen 8083)) {
    & (Join-Path $BotIntegration "start-execution-layer.ps1")
} else {
    Write-Host "JCM sidecars already on 8083-8084"
}

# API (8000)
if (-not (Test-PortListen 8000)) {
    Start-Process -FilePath $Python -ArgumentList "-m","uvicorn","app.main:app","--host","0.0.0.0","--port","8000" `
        -WorkingDirectory $Backend -WindowStyle Hidden
    Write-Host "Started API on :8000"
} else {
    Write-Host "API already on :8000"
}

# Agent worker
$worker = Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "agent_scheduler" }
if (-not $worker) {
    Start-Process -FilePath $Python -ArgumentList "-m","app.workers.agent_scheduler" `
        -WorkingDirectory $Backend -WindowStyle Hidden
    Write-Host "Started agent scheduler"
} else {
    Write-Host "Agent scheduler already running"
}

# Frontend (3000)
if (-not (Test-PortListen 3000) -and $Npm) {
    Start-Process -FilePath $Npm -ArgumentList "run","dev" -WorkingDirectory $Frontend -WindowStyle Hidden
    Write-Host "Started dashboard on :3000"
} elseif (Test-PortListen 3000) {
    Write-Host "Dashboard already on :3000"
}

Start-Sleep -Seconds 5

Write-Host "`n=== Health ===" -ForegroundColor Cyan
try {
    $h = Invoke-RestMethod "http://127.0.0.1:8000/health"
    Write-Host "API: $($h.status) | DB: $($h.database) | Redis: $($h.redis)"
} catch {
    Write-Host "API health FAILED" -ForegroundColor Red
}

$ip = (
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -notlike "127.*" -and
        $_.IPAddress -notlike "169.254.*" -and
        $_.IPAddress -notlike "172.*"
    } |
    Select-Object -First 1
).IPAddress
if (-not $ip) { $ip = "104.194.140.203" }
Write-Host "`nURLs (public IP: $ip):"
Write-Host "  Dashboard:  http://${ip}:3000"
Write-Host "  API:        http://${ip}:8000"
Write-Host "  API Docs:   http://${ip}:8000/docs"
Write-Host "  Webhook:    http://${ip}:8000/ingest/event"
