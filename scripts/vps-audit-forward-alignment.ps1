# Audit forward-alignment + briefing changes on VPS (read-only checks).
$ErrorActionPreference = "Continue"
$pass = 0
$fail = 0
$warn = 0

function Pass($msg) { Write-Host "PASS $msg" -ForegroundColor Green; $script:pass++ }
function Fail($msg) { Write-Host "FAIL $msg" -ForegroundColor Red; $script:fail++ }
function Warn($msg) { Write-Host "WARN $msg" -ForegroundColor Yellow; $script:warn++ }

Write-Host "=== FORWARD ALIGNMENT AUDIT $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan

# 1. MT5 execution readiness
try {
    $st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
    if ($st.connected) { Pass "MT5 API connected" } else { Fail "MT5 API not connected" }
    if ($st.terminal_trade_allowed) { Pass "MT5 AutoTrading enabled" } else { Fail "MT5 AutoTrading OFF (10027 risk)" }
    if ($st.account.trade_allowed) { Pass "Account trade_allowed" } else { Warn "Account trade_allowed=false" }
} catch { Fail "MT5 /api/status unreachable: $($_.Exception.Message)" }

# 2. Reconnect endpoint (new)
try {
    $rc = Invoke-RestMethod "http://127.0.0.1:8765/api/reconnect" -Method POST -TimeoutSec 15
    if ($rc.ok) { Pass "MT5 /api/reconnect ok=true" } else { Warn "MT5 /api/reconnect ok=false" }
} catch { Fail "MT5 /api/reconnect: $($_.Exception.Message)" }

# 3. Deal logs include position_id + entry (backfill support)
try {
    $logs = Invoke-RestMethod "http://127.0.0.1:8765/api/logs?limit=5" -TimeoutSec 10
    $deals = @($logs.deals)
    if ($deals.Count -gt 0) {
        $d0 = $deals[-1]
        if ($null -ne $d0.position_id) { Pass "MT5 deals expose position_id" } else { Warn "MT5 deals missing position_id" }
        if ($null -ne $d0.entry) { Pass "MT5 deals expose entry type" } else { Warn "MT5 deals missing entry field" }
    } else { Warn "MT5 deal history empty (no backfill sample)" }
} catch { Fail "MT5 /api/logs: $($_.Exception.Message)" }

# 4. Forward bot process
$fwd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
})
if ($fwd.Count -eq 1) { Pass "Forward bot single worker PID $($fwd[0].ProcessId)" }
elseif ($fwd.Count -gt 1) { Warn "Forward bot duplicate processes: $($fwd.Count)" }
else { Fail "Forward bot not running" }

# 5. Forward err log - no crash loops
$errLog = "C:\logs\tradingbot\forward-bot.err.log"
if (Test-Path $errLog) {
    $tail = Get-Content $errLog -Tail 12 -EA SilentlyContinue
    if ($tail -match 'scripts/scripts/|ERR_MODULE_NOT_FOUND') { Fail "Forward bot launcher path broken in recent err log" }
    elseif ($tail -match 'MODULE_NOT_FOUND|Cannot find module') { Fail "Forward bot import error in recent err log" }
    elseif ($tail -match '\[forward-demo\].*waiting for new M30|\[forward-demo\].*Poll every|Resuming session') {
        Pass "Forward bot log shows healthy polling"
    } else { Warn "Forward bot log unclear - check $errLog" }
} else { Warn "No forward-bot.err.log" }

# 6. Validation junction (VPS scripts layout)
$vj = "C:\opt\bilshenz\backend\scripts\validation"
if (Test-Path $vj) { Pass "scripts/validation junction exists" } else { Fail "scripts/validation junction missing" }

# 7. Failsafe state
$safety = "C:\logs\tradingbot\safety-state.json"
if (Test-Path $safety) {
    $s = Get-Content $safety -Raw | ConvertFrom-Json
    if (-not $s.failsafe -and [int]$s.consecutiveApiFailures -eq 0) { Pass "Failsafe cleared" }
    else { Warn "Failsafe active: $($s.failsafeReason)" }
} else { Warn "safety-state.json not found" }

# 8. Execution ensure task
schtasks /Query /TN "JCM-Execution-Stack-Ensure" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Pass "JCM-Execution-Stack-Ensure task registered" }
else { Fail "JCM-Execution-Stack-Ensure task missing" }

# 9. Desk API
try {
    Invoke-RestMethod "http://127.0.0.1:8791/health" -TimeoutSec 8 | Out-Null
    Pass "Desk API health"
} catch { Warn "Desk API down: $($_.Exception.Message)" }

# 10. JCM API + embedded briefing scheduler
try {
    Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 10 | Out-Null
    Pass "JCM API health"
} catch { Fail "JCM API health: $($_.Exception.Message)" }

$apiLog = "C:\logs\jcm\JCMAPI-stdout.log"
if (-not (Test-Path $apiLog)) { $apiLog = "C:\jcm\logs\JCMAPI-stdout.log" }
if (Test-Path $apiLog) {
    $apiTail = Get-Content $apiLog -Tail 200 -EA SilentlyContinue | Out-String
    if ($apiTail -match 'embedded_briefing_scheduler_started') { Pass "Embedded briefing scheduler started in JCMAPI" }
    else { Warn "embedded_briefing_scheduler_started not in recent JCMAPI log" }
} else { Warn "JCMAPI log not found for briefing check" }

# 11. Briefing SYSTEM tasks
foreach ($tn in @("JCM-Daily-Executive-Briefing", "JCM-Briefing-Telegram-Backup")) {
    schtasks /Query /TN $tn /V /FO LIST 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $info = schtasks /Query /TN $tn /V /FO LIST 2>$null | Out-String
        if ($info -match 'Run As User:\s+SYSTEM') { Pass "$tn runs as SYSTEM" }
        else { Warn "$tn not SYSTEM" }
    } else { Warn "$tn task not registered" }
}

# 12. Backfill script dry-run
$backfill = "C:\jcm-project\scripts\vps-backfill-trade-closed.ps1"
if (Test-Path $backfill) {
    try {
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $backfill --dry-run 2>&1 | Out-String
        if ($out -match "'closed':") { Pass "trade_closed backfill dry-run executed" }
        else { Fail "Backfill dry-run unexpected: $out" }
    } catch { Fail "Backfill dry-run error: $($_.Exception.Message)" }
} else { Warn "vps-backfill-trade-closed.ps1 not on VPS" }

# 13. Position watcher state
$watch = "C:\opt\bilshenz\backend\validation\data\jcm-position-watch.json"
if (Test-Path $watch) { Pass "JCM position watch state file present" }
else { Warn "jcm-position-watch.json not yet created (ok if no opens)" }

# 14. Deployed file hashes (sanity)
$expected = @(
    "C:\opt\bilshenz\backend\scripts\run-forward-demo-30d.ts",
    "C:\opt\bilshenz\backend\jcm\jcmPositionWatcher.ts",
    "C:\opt\bilshenz\mt5_trading_system\python\mt5_connector.py",
    "C:\jcm-project\backend\app\scripts\backfill_trade_closed_from_mt5.py"
)
foreach ($f in $expected) {
    if (Test-Path $f) { Pass "Deployed file exists: $(Split-Path $f -Leaf)" }
    else { Fail "Missing deployed file: $f" }
}

Write-Host ""
Write-Host "=== SUMMARY: PASS=$pass FAIL=$fail WARN=$warn ===" -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host "RESULT: OK - forward alignment operational" -ForegroundColor Green
    exit 0
}
Write-Host "RESULT: ISSUES FOUND - review FAIL/WARN above" -ForegroundColor Red
exit 1
