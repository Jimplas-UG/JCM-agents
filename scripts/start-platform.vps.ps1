#Requires -Version 5.1
<#
.SYNOPSIS
  Start API, agent worker, and dashboard on Windows.
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LogDir = Join-Path $Root "backend\logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Load .env into process environment
foreach ($line in Get-Content (Join-Path $Root ".env")) {
    if ($line -match '^\s*([^#][^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
    }
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
    $out = Join-Path $LogDir $logFile
    $err = Join-Path $LogDir ($logFile -replace '\.log$', '.err.log')
    Start-Process -FilePath "python" `
        -ArgumentList $argList `
        -WorkingDirectory $workDir `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err `
        -WindowStyle Hidden
    Write-Host "Started $label -> $out"
}

# API
Start-JcmPython "API (uvicorn)" "uvicorn app\.main:app" "$Root\backend" @(
    "-m", "uvicorn", "app.main:app",
    "--host", "0.0.0.0", "--port", "8000", "--workers", "1"
) "api.log"

Start-Sleep -Seconds 3

# Agent scheduler (all 9 agents)
Start-JcmPython "Agent scheduler" "app\.workers\.agent_scheduler" "$Root\backend" @(
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
    $npmCmd = (Get-Command npm.cmd -ErrorAction SilentlyContinue).Source
    if (-not $npmCmd) { $npmCmd = "npm.cmd" }
    Start-Process -FilePath $npmCmd `
        -ArgumentList "start" `
        -WorkingDirectory (Join-Path $Root "frontend") `
        -RedirectStandardOutput $feOut `
        -RedirectStandardError $feErr `
        -WindowStyle Hidden
    Write-Host "Started dashboard -> $feOut"
} else {
    $p = (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    Write-Host "Dashboard already running (PID $p)"
}

Start-Sleep -Seconds 5
try {
    $h = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 10
    Write-Host "API health: $($h.status)" -ForegroundColor Green
} catch {
    Write-Host "API not responding yet - check backend\logs\api.err.log" -ForegroundColor Yellow
}

$pub = $env:PLATFORM_PUBLIC_URL
if (-not $pub) { $pub = "http://localhost:8000" }
Write-Host "Dashboard: $($pub -replace ':8000', ':3000')"
