# Ensure forward bot + execution stack running — does NOT modify strategy code
$ErrorActionPreference = "Continue"
$LogDir = "C:\logs\tradingbot"
$ef = "C:\ProgramData\Bilshenz\tradingbot.env"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log($m) {
    $l = "[$(Get-Date -Format HH:mm:ss)] $m"
    Write-Host $l
    Add-Content "C:\Users\Administrator\ensure-forward.log" $l
}

Log "=== ENSURE EXECUTION STACK ==="

# Load env
if (Test-Path $ef) {
    Get-Content $ef | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
        }
    }
}

# 1. Windows services for JCM only
foreach ($svc in @("postgresql-x64-17", "Memurai")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Start-Service $svc; Log "Started $svc" }
}

# 2. MT5 terminal if down
$mt5Path = $env:MT5_TERMINAL_PATH
if (-not $mt5Path) { $mt5Path = "C:\Program Files\MetaTrader 5 Exness" }
$term = Join-Path $mt5Path "terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -ErrorAction SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"
    Log "Started MT5 terminal"
    Start-Sleep -Seconds 20
}

# 3. Bilshenz services via tasks (never kill python globally)
function Ensure-Port([int]$port, [string]$task) {
    $up = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $up) {
        Log "Port $port down — running $task"
        schtasks /Run /TN $task 2>&1 | Out-Null
        Start-Sleep -Seconds 15
    } else {
        Log "Port $port OK"
    }
}

Ensure-Port 8765 "Bilshenz-MT5-API"
Ensure-Port 8791 "Bilshenz-DeskAPI"

# 4. Forward bot — single worker only
$fwdProcs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match "run-forward-demo-30d"
})
if ($fwdProcs.Count -gt 1) {
    $keep = $fwdProcs[-1].ProcessId
    foreach ($p in $fwdProcs[0..($fwdProcs.Count-2)]) {
        Log "Killing duplicate forward PID $($p.ProcessId)"
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
}
if ($fwdProcs.Count -eq 0) {
    Log "Forward bot not running — starting Bilshenz-ForwardBot task"
    schtasks /Run /TN "Bilshenz-ForwardBot" 2>&1 | Out-Null
    Start-Sleep -Seconds 20
} else {
    Log "Forward bot running PID $($fwdProcs[0].ProcessId)"
}

# 5. Bilshenz watchdog (production — polls MT5/desk/forward)
$wdTask = Get-ScheduledTask -TaskName "Bilshenz-Watchdog" -ErrorAction SilentlyContinue
if ($wdTask -and $wdTask.State -ne "Running") {
    schtasks /Run /TN "Bilshenz-Watchdog" 2>&1 | Out-Null
    Log "Started Bilshenz-Watchdog"
}

# 6. JCM observability (sidecars only — not trading)
& "C:\Users\Administrator\start-sidecars.ps1" 2>&1 | ForEach-Object { Log $_ }

# 7. Clear failsafe if MT5 healthy
Start-Sleep -Seconds 5
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
    $safety = "C:\logs\tradingbot\safety-state.json"
    $execReady = $m.connected -and $m.terminal_trade_allowed -and $m.account.trade_allowed
    if (-not $m.terminal_trade_allowed) {
        Log "WARN: MT5 AutoTrading OFF — restarting terminal with /algotrading"
        taskkill /f /im terminal64.exe 2>$null
        Start-Sleep -Seconds 8
        Start-Process $term -ArgumentList "/algotrading"
        Start-Sleep -Seconds 45
    }
    if ($execReady -and (Test-Path $safety)) {
        $state = Get-Content $safety -Raw | ConvertFrom-Json
        if ($state.failsafe -or $state.consecutiveApiFailures -gt 0) {
            $state.consecutiveApiFailures = 0
            $state.failsafe = $false
            $state.failsafeReason = $null
            $state | ConvertTo-Json | Set-Content $safety -Encoding UTF8
            Log "Cleared failsafe — MT5 connected"
        }
    }
} catch { Log "MT5 check skipped: $($_.Exception.Message)" }

# 8. JCM 9-agent scheduler (Mission Control data freshness)
$agentStarter = "C:\jcm-project\scripts\vps-start-agent-scheduler.ps1"
if (Test-Path $agentStarter) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $agentStarter 2>&1 | ForEach-Object { Log $_ }
}

# 9. Health summary
Log "--- SUMMARY ---"
try {
    $tick = Invoke-RestMethod "http://127.0.0.1:8765/api/tick/XAUUSD" -TimeoutSec 8
    Log "Tick age OK symbol=XAUUSD"
} catch { Log "Tick check failed" }

$fwd2 = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match "run-forward-demo"
}
Log "Forward process count: $($fwd2.Count)"
Log "FORWARD_DRY_RUN=$($env:FORWARD_DRY_RUN) PRODUCTION_MODE=$($env:PRODUCTION_MODE)"
Log "=== DONE ==="
