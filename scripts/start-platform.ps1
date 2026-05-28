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

function Start-JcmProcess($name, $workDir, $argList, $logFile) {
    $existing = Get-Process -Name $name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "$name already running (PID $($existing.Id))"
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
    Write-Host "Started $name -> $out"
}

# API
Start-JcmProcess "uvicorn" "$Root\backend" @(
    "-m", "uvicorn", "app.main:app",
    "--host", "0.0.0.0", "--port", "8000", "--workers", "1"
) "api.log"

Start-Sleep -Seconds 3

# Agent scheduler (all 9 agents)
Start-JcmProcess "agent_scheduler" "$Root\backend" @(
    "-m", "app.workers.agent_scheduler"
) "agents-worker.log"

# Dashboard
$feProc = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
    $_.Path -like "*frontend*"
}
if (-not $feProc) {
    $feOut = Join-Path $LogDir "frontend.log"
    $feErr = Join-Path $LogDir "frontend.err.log"
    Start-Process -FilePath "cmd.exe" `
        -ArgumentList "/c", "cd /d `"$Root\frontend`" && npm start" `
        -RedirectStandardOutput $feOut `
        -RedirectStandardError $feErr `
        -WindowStyle Hidden
    Write-Host "Started dashboard -> $feOut"
}

Start-Sleep -Seconds 5
try {
    $h = Invoke-RestMethod -Uri "http://127.0.0.1:8000/health" -TimeoutSec 10
    Write-Host "API health: $($h.status)" -ForegroundColor Green
} catch {
    Write-Host "API not responding yet - check backend\logs\api.log" -ForegroundColor Yellow
}

$pub = $env:PLATFORM_PUBLIC_URL
if (-not $pub) { $pub = "http://localhost:8000" }
Write-Host "Dashboard: $($pub -replace ':8000', ':3000')"
