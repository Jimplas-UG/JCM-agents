# Ensure forward bot + execution stack + executive briefing — does NOT modify strategy code
$ErrorActionPreference = "Continue"
$LogDir = "C:\logs\tradingbot"
$ef = "C:\ProgramData\Bilshenz\tradingbot.env"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$tsxHelper = "C:\jcm-project\scripts\vps-tsx-worker.ps1"
if (Test-Path $tsxHelper) { . $tsxHelper }

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

# 3. Forward validation junction (scripts/ layout on VPS)
$vj = "C:\opt\bilshenz\backend\scripts\validation"
$vt = "C:\opt\bilshenz\backend\validation"
if ((Test-Path $vt) -and -not (Test-Path $vj)) {
    cmd /c mklink /J "$vj" "$vt" 2>$null
    Log "Linked scripts/validation -> validation"
}
$fwdLauncher = "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
$wdLauncher = "C:\opt\bilshenz\deploy\windows\run-watchdog.ps1"
$repoLauncher = "C:\jcm-project\run-forward-bot.vps.ps1"
$repoWatchdog = "C:\jcm-project\run-watchdog.vps.ps1"
if (Test-Path $repoLauncher) {
    Copy-Item $repoLauncher $fwdLauncher -Force
    Log "Synced run-forward-bot.ps1 from jcm-project"
}
if (Test-Path $repoWatchdog) {
    Copy-Item $repoWatchdog $wdLauncher -Force
    Log "Synced run-watchdog.ps1 from jcm-project"
}
$tsxSrc = "C:\jcm-project\scripts\vps-tsx-worker.ps1"
if (Test-Path $tsxSrc) {
    Copy-Item $tsxSrc "C:\jcm\scripts\vps-tsx-worker.ps1" -Force -EA SilentlyContinue
    Copy-Item $tsxSrc "C:\opt\bilshenz\deploy\windows\vps-tsx-worker.ps1" -Force -EA SilentlyContinue
}
$wdDeploy = "C:\opt\bilshenz\deploy\watchdog.ts"
$wdRepo = "C:\jcm-project\watchdog.vps.ts"
if ((Test-Path $wdRepo) -and -not (Test-Path $wdDeploy)) {
    Copy-Item $wdRepo $wdDeploy -Force
    Log "Synced deploy/watchdog.ts from jcm-project"
} elseif ((Test-Path $wdRepo)) {
    Copy-Item $wdRepo $wdDeploy -Force
    Log "Updated deploy/watchdog.ts from jcm-project"
}
if (-not (Test-Path $repoLauncher) -and (Test-Path $fwdLauncher)) {
    $raw = Get-Content $fwdLauncher -Raw
    $raw = $raw -replace 'scripts/scripts/run-forward-demo-30d\.ts', 'scripts/run-forward-demo-30d.ts'
    $raw = $raw -replace '(?s)function Test-ForwardAlive \{.*?\n\}', @'
function Test-ForwardAlive {
    $node = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
    }
    return [bool]$node
}
'@
    Set-Content $fwdLauncher $raw -Encoding UTF8
    Log "Patched forward launcher on VPS"
}

# 4. Bilshenz services via tasks (never kill python globally)
function Ensure-Port([int]$port, [string]$task) {
    $up = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $up) {
        Log "Port $port down - running $task"
        schtasks /Run /TN $task 2>&1 | Out-Null
        Start-Sleep -Seconds 15
    } else {
        Log "Port $port OK"
    }
}

function Run-TaskIfExists([string]$name) {
    schtasks /Query /TN $name 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        schtasks /Run /TN $name 2>&1 | Out-Null
        return $true
    }
    return $false
}

if (-not (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue)) {
    Log "Port 8765 down - starting MT5 API task"
    if (-not (Run-TaskIfExists "Bilshenz-MT5-API-Sys")) { Run-TaskIfExists "Bilshenz-MT5-API" | Out-Null }
    Start-Sleep -Seconds 15
} else {
    Log "Port 8765 OK"
}
if (-not (Get-NetTCPConnection -LocalPort 8791 -State Listen -ErrorAction SilentlyContinue)) {
    Log "Port 8791 down - starting Desk API task"
    if (-not (Run-TaskIfExists "Bilshenz-DeskAPI-Sys")) { Run-TaskIfExists "Bilshenz-DeskAPI" | Out-Null }
    Start-Sleep -Seconds 15
} else {
    Log "Port 8791 OK"
}
try {
    Invoke-RestMethod "http://127.0.0.1:8765/api/reconnect" -Method POST -TimeoutSec 20 | Out-Null
    Log "MT5 API reconnect OK"
} catch {
    Log "MT5 reconnect skipped: $($_.Exception.Message)"
}

# 5. Forward bot — never re-run launcher if leaf worker alive (tsx = 2 node PIDs)
$fwdMarker = 'run-forward-demo-30d'
$fwdRunning = $false
if (Get-Command Test-TsxWorkerRunning -EA SilentlyContinue) {
    $fwdRunning = Test-TsxWorkerRunning $fwdMarker
    if ($fwdRunning) { Stop-TsxWorkerDuplicates $fwdMarker | Out-Null }
} else {
    $fwdProcs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match $fwdMarker
    })
    $fwdRunning = $fwdProcs.Count -ge 2
}
if (-not $fwdRunning) {
    Log "Forward bot not running - starting via launcher"
    if (Test-Path $fwdLauncher) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $fwdLauncher -AppDir "C:\opt\bilshenz" 2>&1 | ForEach-Object { Log $_ }
        Start-Sleep -Seconds 12
    } else {
        Run-TaskIfExists "Bilshenz-ForwardBot-Sys" | Out-Null
        Start-Sleep -Seconds 20
    }
} else {
    $leaves = if (Get-Command Get-TsxWorkerLeaves -EA SilentlyContinue) { Get-TsxWorkerLeaves $fwdMarker } else { @() }
    if ($leaves.Count -gt 1) {
        Log "WARN: $($leaves.Count) forward workers - restarting single instance"
        Stop-TsxWorkerAll $fwdMarker
        Start-Sleep 3
        & powershell -NoProfile -ExecutionPolicy Bypass -File $fwdLauncher -AppDir "C:\opt\bilshenz" 2>&1 | ForEach-Object { Log $_ }
    } else {
        $n = if (Get-Command Get-TsxWorkerNodeCount -EA SilentlyContinue) { Get-TsxWorkerNodeCount $fwdMarker } else { 2 }
        Log "Forward bot running ($n node PIDs, tsx parent+child)"
    }
}

# 6. Bilshenz watchdog
$wdMarker = 'watchdog\.ts'
$wdRunning = $false
if (Get-Command Test-TsxWorkerRunning -EA SilentlyContinue) {
    $wdRunning = Test-TsxWorkerRunning $wdMarker
    if ($wdRunning) { Stop-TsxWorkerDuplicates $wdMarker | Out-Null }
} else {
    $wdRunning = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -match $wdMarker
    }).Count -ge 2
}
if (-not $wdRunning) {
    Log "Watchdog not running - starting via launcher"
    if (Test-Path $wdLauncher) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $wdLauncher -AppDir "C:\opt\bilshenz" 2>&1 | ForEach-Object { Log $_ }
        Start-Sleep -Seconds 10
    } else {
        Run-TaskIfExists "Bilshenz-Watchdog-Sys" | Out-Null
        Start-Sleep -Seconds 12
    }
} else {
    Log "Watchdog running"
}

# 7. JCM observability (sidecars only - not trading) — quick, non-blocking
if (Test-Path "C:\Users\Administrator\start-sidecars.ps1") {
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', 'C:\Users\Administrator\start-sidecars.ps1'
    ) -WindowStyle Hidden
    Log "Spawned sidecars check (background)"
}

# 8. Clear failsafe if MT5 healthy
Start-Sleep -Seconds 5
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
    $safety = "C:\logs\tradingbot\safety-state.json"
    $execReady = $m.connected -and $m.terminal_trade_allowed -and $m.account.trade_allowed
    if (-not $m.terminal_trade_allowed) {
        Log "WARN: MT5 AutoTrading OFF - restarting terminal with /algotrading"
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
            Log "Cleared failsafe - MT5 connected"
        }
    }
} catch { Log "MT5 check skipped: $($_.Exception.Message)" }

# 9. JCM 9-agent scheduler (Mission Control data freshness) — background
$agentStarter = "C:\jcm-project\scripts\vps-start-agent-scheduler.ps1"
if (Test-Path $agentStarter) {
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $agentStarter
    ) -WindowStyle Hidden
    Log "Spawned agent scheduler check (background)"
}

# 10. Allocator pipeline (backfill + tear sheet) — daily
$allocatorMarker = "C:\logs\tradingbot\last-allocator-pipeline.txt"
$runAllocator = $false
$allocatorScript = "C:\jcm-project\scripts\vps-run-allocator-pipeline.ps1"
if (Test-Path $allocatorScript) {
    if (-not (Test-Path $allocatorMarker)) { $runAllocator = $true }
    else {
        $lastA = (Get-Item $allocatorMarker).LastWriteTime
        if ((Get-Date) - $lastA -gt [TimeSpan]::FromHours(24)) { $runAllocator = $true }
    }
}
if ($runAllocator) {
    Log "Spawning allocator pipeline (background)..."
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $allocatorScript
    ) -WindowStyle Hidden
    New-Item -ItemType File -Force -Path $allocatorMarker | Out-Null
}

# 11. Institutional ops telemetry
$riskPct = if ($env:RISK_PCT) { [double]$env:RISK_PCT * 100 } else { 1.0 }
Log "RISK_PCT=$riskPct% CONSECUTIVE_LOSS_LIMIT=$($env:CONSECUTIVE_LOSS_LIMIT)"

$jsonl = "C:\opt\bilshenz\backend\validation\data\forward-demo-events.jsonl"
if (Test-Path $jsonl) {
    $signals = 0; $fills = 0
    Get-Content $jsonl -Tail 5000 -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_ -match '"type"\s*:\s*"SIGNAL"') { $signals++ }
        if ($_ -match '"type"\s*:\s*"ORDER_FILL"') { $fills++ }
    }
    if ($signals -gt 0) {
        $fillPct = [math]::Round(($fills / $signals) * 100, 1)
        Log "Signal-to-fill (tail): $fillPct% ($fills/$signals)"
    }
}

$readinessScript = "C:\jcm-project\scripts\vps-run-institutional-readiness.ps1"
$readinessMarker = "C:\logs\tradingbot\last-readiness-run.txt"
$runReadiness = $false
if (Test-Path $readinessScript) {
    if (-not (Test-Path $readinessMarker)) { $runReadiness = $true }
    else {
        $last = (Get-Item $readinessMarker).LastWriteTime
        if ((Get-Date) - $last -gt [TimeSpan]::FromHours(24)) { $runReadiness = $true }
    }
}
if ($runReadiness) {
    Log "Spawning institutional readiness report (background)..."
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $readinessScript
    ) -WindowStyle Hidden
    New-Item -ItemType File -Force -Path $readinessMarker | Out-Null
}

# 13. Executive briefing (JCMAPI embedded scheduler + catchup)
$nssm = "C:\jcm\nssm\nssm.exe"
if (Test-Path $nssm) {
    try {
        $apiSt = (& $nssm status JCMAPI 2>&1 | Out-String).Trim()
        if ($apiSt -notmatch 'SERVICE_RUNNING') {
            Log "JCMAPI down ($apiSt) - restarting"
            & $nssm restart JCMAPI confirm 2>&1 | ForEach-Object { Log $_ }
            Start-Sleep -Seconds 15
        } else {
            Log "JCMAPI running"
        }
    } catch { Log "JCMAPI check skipped: $($_.Exception.Message)" }
}

$briefCatchup = "C:\jcm\scripts\vps-briefing-startup-catchup.ps1"
if (-not (Test-Path $briefCatchup)) { $briefCatchup = "C:\jcm-project\scripts\vps-briefing-startup-catchup.ps1" }
if (Test-Path $briefCatchup) {
    try {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("E. Africa Standard Time")
        $nowK = [System.TimeZoneInfo]::ConvertTimeFromUtc((Get-Date).ToUniversalTime(), $tz)
        $todayK = $nowK.ToString("yyyy-MM-dd")
        if ($nowK.Hour -ge 9) {
            $briefLog = "C:\logs\jcm\daily-briefing-telegram.log"
            $sentToday = $false
            if (Test-Path $briefLog) {
                $sentToday = Select-String -Path $briefLog -Pattern "$todayK.*SUCCESS" -Quiet -EA SilentlyContinue
            }
            if (-not $sentToday) {
                Log "Executive briefing not sent for $todayK (Kampala) - spawning catchup (background)"
                Start-Process powershell.exe -ArgumentList @(
                    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $briefCatchup
                ) -WindowStyle Hidden
            } else {
                Log "Executive briefing sent today ($todayK)"
            }
        }
    } catch { Log "Briefing ensure skipped: $($_.Exception.Message)" }
}

# 12. Health summary
Log "--- SUMMARY ---"
try {
    $tick = Invoke-RestMethod "http://127.0.0.1:8765/api/tick/XAUUSD" -TimeoutSec 8
    Log "Tick age OK symbol=XAUUSD"
} catch { Log "Tick check failed" }

$fwd2 = if (Get-Command Test-TsxWorkerRunning -EA SilentlyContinue) {
    if (Test-TsxWorkerRunning 'run-forward-demo-30d') { Get-TsxWorkerNodeCount 'run-forward-demo-30d' } else { 0 }
} else {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "run-forward-demo" }).Count
}
$wd2 = if (Get-Command Test-TsxWorkerRunning -EA SilentlyContinue) {
    if (Test-TsxWorkerRunning 'watchdog\.ts') { Get-TsxWorkerNodeCount 'watchdog\.ts' } else { 0 }
} else {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "watchdog\.ts" }).Count
}
Log "Forward: $(if (Get-Command Test-TsxWorkerRunning -EA SilentlyContinue) { Test-TsxWorkerRunning 'run-forward-demo-30d' } else { $fwd2 -ge 2 }) ($fwd2 node PIDs)"
Log "Watchdog: $(if (Get-Command Test-TsxWorkerRunning -EA SilentlyContinue) { Test-TsxWorkerRunning 'watchdog\.ts' } else { $wd2 -ge 2 }) ($wd2 node PIDs)"
if (Test-Path "C:\logs\tradingbot\watchdog.log") {
    $wdAge = ((Get-Date) - (Get-Item "C:\logs\tradingbot\watchdog.log").LastWriteTime).TotalMinutes
    Log ("Watchdog log age min: {0:N1}" -f $wdAge)
}
Log "FORWARD_DRY_RUN=$($env:FORWARD_DRY_RUN) PRODUCTION_MODE=$($env:PRODUCTION_MODE)"
Log "=== DONE ==="
