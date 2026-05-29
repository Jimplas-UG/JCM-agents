#Requires -Version 5.1
<#
.SYNOPSIS
  Start API, agent worker, dashboard, and sidecars on Windows.
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Backend = Join-Path $Root "backend"
$Frontend = Join-Path $Root "frontend"
$BotIntegration = Join-Path $Root "infra\bot-integration"
$LogDir = Join-Path $Backend "logs"
$Python = Join-Path $Backend ".venv\Scripts\python.exe"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Test-PortListen([int]$port) {
    return [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

Write-Host "=== JCM Platform Startup ===" -ForegroundColor Cyan

# Load .env into process environment
foreach ($line in Get-Content (Join-Path $Root ".env")) {
    if ($line -match '^\s*([^#][^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
    }
}

foreach ($svc in @("postgresql-x64-17", "Memurai")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Start-Service $svc; Write-Host "Started $svc" }
}

Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force
Copy-Item (Join-Path $Root ".env") (Join-Path $Frontend ".env.local") -Force

if (-not (Test-PortListen 8083)) {
    & (Join-Path $BotIntegration "start-execution-layer.ps1")
} else {
    Write-Host "JCM sidecars already on 8083-8084"
}

function Test-JcmPythonRunning([string]$pattern) {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $pattern } |
        Select-Object -First 1
}

function Start-JcmPython([string]$label, [string]$matchPattern, [string]$workDir, [string[]]$argList, [string]$logFile) {
    $existing = Test-JcmPythonRunning $matchPattern
    if ($existing) {
        Write-Host "$label already running (PID $($existing.ProcessId))"
        return
    }
    $py = if (Test-Path $Python) { $Python } else { "python" }
    $out = Join-Path $LogDir $logFile
    $err = Join-Path $LogDir ($logFile -replace '\.log$', '.err.log')
    Start-Process -FilePath $py `
        -ArgumentList $argList `
        -WorkingDirectory $workDir `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden
    Write-Host "Started $label -> $out"
}

# API
Start-JcmPython "API (uvicorn)" "uvicorn app\.main:app" $Backend @(
    "-m", "uvicorn", "app.main:app",
    "--host", "0.0.0.0", "--port", "8000", "--workers", "1"
) "api.log"

Start-Sleep -Seconds 3

# Agent scheduler (all 9 agents)
Start-JcmPython "Agent scheduler" "app\.workers\.agent_scheduler" $Backend @(
    "-m", "app.workers.agent_scheduler"
) "agents-worker.log"

# Dashboard — free port 3000 if an old Next process is still bound
$port3000 = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($port3000) {
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($port3000.OwningProcess)" -ErrorAction SilentlyContinue
    if ($owner -and $owner.CommandLine -notmatch 'JCM-agents') {
        Write-Host "Port 3000 in use by non-JCM process PID $($port3000.OwningProcess) - leaving it"
    } else {
        Write-Host "Releasing stale dashboard on port 3000 (PID $($port3000.OwningProcess))"
        Stop-Process -Id $port3000.OwningProcess -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

$dashRunning = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
if (-not $dashRunning) {
    $feOut = Join-Path $LogDir "frontend.log"
    $feErr = Join-Path $LogDir "frontend.err.log"
    $standaloneDir = Join-Path $Frontend ".next\standalone"
    $standalone = Join-Path $standaloneDir "server.js"
    if (Test-Path $standalone) {
        $staticSrc = Join-Path $Frontend ".next\static"
        $staticDst = Join-Path $standaloneDir ".next\static"
        if (Test-Path $staticSrc) {
            New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
            Copy-Item -Recurse -Force $staticSrc $staticDst -ErrorAction SilentlyContinue
        }
        $pubSrc = Join-Path $Frontend "public"
        $pubDst = Join-Path $standaloneDir "public"
        if (Test-Path $pubSrc) {
            Copy-Item -Recurse -Force $pubSrc $pubDst -ErrorAction SilentlyContinue
        }
        $env:PORT = "3000"
        $env:HOSTNAME = "0.0.0.0"
        Start-Process -FilePath "node" -ArgumentList "server.js" -WorkingDirectory $standaloneDir `
            -RedirectStandardOutput $feOut -RedirectStandardError $feErr -WindowStyle Hidden
        Write-Host "Started dashboard (standalone) -> $feOut"
    } else {
        $npmCmd = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
        if (-not $npmCmd) { $npmCmd = "npm.cmd" }
        Start-Process -FilePath $npmCmd `
            -ArgumentList "start" `
            -WorkingDirectory $Frontend `
            -RedirectStandardOutput $feOut `
            -RedirectStandardError $feErr `
            -WindowStyle Hidden
        Write-Host "Started dashboard -> $feOut"
    }
} else {
    $p = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    Write-Host "Dashboard already running (PID $p)"
}

Start-Sleep -Seconds 5
try {
    $h = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 10
    Write-Host "API: $($h.status) | DB: $($h.database) | Redis: $($h.redis)" -ForegroundColor Green
} catch {
    Write-Host "API not responding yet - check backend\logs\api.err.log" -ForegroundColor Yellow
}

$pub = $env:PLATFORM_PUBLIC_URL
if (-not $pub) {
    $ip = $env:PLATFORM_HOST
    if ($ip) { $pub = "http://${ip}:8000" } else { $pub = "http://localhost:8000" }
}
Write-Host "Dashboard:  $($pub -replace ':8000', ':3000')"
Write-Host "Mission Ctrl: $($pub -replace ':8000|:3000', ''):8000/mission-control"
Write-Host "API:          $pub"
