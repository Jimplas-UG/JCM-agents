# End-to-end forward + watchdog test (run on VPS)
$ErrorActionPreference = "Continue"
$testStart = Get-Date
$pass = 0
$fail = 0

function Assert([bool]$ok, [string]$name, [string]$detail = "") {
    if ($ok) {
        Write-Host "[PASS] $name" -ForegroundColor Green
        if ($detail) { Write-Host "       $detail" }
        $script:pass++
    } else {
        Write-Host "[FAIL] $name" -ForegroundColor Red
        if ($detail) { Write-Host "       $detail" }
        $script:fail++
    }
}

Write-Host "=== FORWARD + WATCHDOG TEST ===" -ForegroundColor Cyan

# 1. MT5 + desk API
try {
    $mt5 = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
    Assert ($mt5.connected) "MT5 API connected" "server=$($mt5.server)"
    Assert ($mt5.terminal_trade_allowed) "MT5 AutoTrading on"
} catch {
    Assert $false "MT5 API reachable" $_.Exception.Message
}

try {
    $desk = Invoke-RestMethod "http://127.0.0.1:8791/health" -TimeoutSec 8
    Assert $true "Desk API up"
} catch {
    Assert $false "Desk API up" $_.Exception.Message
}

# 2. Start workers if down
$f0 = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'run-forward-demo-30d'
}).Count
$w0 = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'watchdog\.ts'
}).Count

if ($f0 -lt 2 -or $w0 -lt 2) {
    Write-Host "Starting workers (fwd=$f0 wd=$w0)..." -ForegroundColor Yellow
    & "C:\Users\Administrator\vps-start-forward-watchdog.ps1"
    Start-Sleep 12
}

$fStart = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'run-forward-demo-30d'
}).Count
$wStart = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'watchdog\.ts'
}).Count
Assert ($fStart -ge 2) "Forward bot running after start" "node PIDs=$fStart (2=tsx parent+child)"
Assert ($wStart -ge 2) "Watchdog running after start" "node PIDs=$wStart"

$errLog = "C:\logs\tradingbot\forward-bot.err.log"
$fwdMtimeStart = if (Test-Path $errLog) { (Get-Item $errLog).LastWriteTime } else { $null }

# 3. Wait 90s — forward should poll and log; processes should stay up
Write-Host "Waiting 90s for poll + stability..." -ForegroundColor DarkGray
Start-Sleep -Seconds 90

$fEnd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'run-forward-demo-30d'
}).Count
$wEnd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'watchdog\.ts'
}).Count
Assert ($fEnd -ge 2) "Forward bot stable 90s" "node PIDs=$fEnd"
Assert ($wEnd -ge 2) "Watchdog stable 90s" "node PIDs=$wEnd"

if (Test-Path $errLog) {
    $fwdMtimeEnd = (Get-Item $errLog).LastWriteTime
    $ageSec = ((Get-Date) - $fwdMtimeEnd).TotalSeconds
    Assert ($ageSec -lt 120) "Forward log fresh (<120s)" "last write ${ageSec}s ago"
    Write-Host "--- forward err tail ---"
    Get-Content $errLog -Tail 3
}

$wdLog = "C:\logs\tradingbot\watchdog.log"
if (Test-Path $wdLog) {
    $wdAge = ((Get-Date) - (Get-Item $wdLog).LastWriteTime).TotalMinutes
    Assert ($wdAge -lt 10) "Watchdog log updated (<10min)" "${wdAge} min ago"
    Write-Host "--- watchdog tail ---"
    Get-Content $wdLog -Tail 4
}

# 4. Watchdog must NOT kill forward during this test
if (Test-Path $wdLog) {
    $kills = @(Get-Content $wdLog -Tail 50 -EA SilentlyContinue | Where-Object { $_ -match 'Killing duplicate forward' })
    $newKills = @($kills | Where-Object {
        if ($_ -match '^(\d{4}-\d{2}-\d{2}T[\d:.]+Z?)') {
            try { [datetime]::Parse($Matches[1].TrimEnd('Z')) -ge $testStart.AddMinutes(-1) } catch { $false }
        } else { $false }
    })
    Assert ($newKills.Count -eq 0) "No duplicate-kill during test" "found $($newKills.Count) new kill lines"
}

Write-Host ""
Write-Host "=== RESULT: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { "Green" } else { "Red" })
exit $(if ($fail -eq 0) { 0 } else { 1 })
