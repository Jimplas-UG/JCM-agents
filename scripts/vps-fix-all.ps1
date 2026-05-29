# Full VPS remediation: start all stacks, sync env, remove Cursor, verify health
$ErrorActionPreference = "Continue"
$JcmRoot = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Bilshenz = "C:\opt\bilshenz"
$LogFile = "C:\Users\Administrator\vps-fix-$(Get-Date -Format yyyyMMdd-HHmmss).log"

function Log($msg) {
    $line = "[$(Get-Date -Format HH:mm:ss)] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

Log "=== VPS FIX START ==="

# 1. Complete bot-integration env (sidecar stubs need webhook + keys)
$botEnv = Join-Path $JcmRoot "infra\bot-integration\bsv32-forward-bot.env"
$botContent = @"
# Auto-synced for JCM infra_resilience health checks + webhook emit
JCM_INGEST_WEBHOOK_URL=http://127.0.0.1:8000/ingest/event
JCM_WEBHOOK_SECRET=26nvWoyYBrR4GMuNZeaFLJP1OXc75Idi
FORWARD_BOT_API_KEY=jcm_s930px6rvhanj7kt5qi8fy41ocdu
WATCHDOG_API_KEY=jcm_caxs285n7flj0t4muord1z63hgbi
MT5_API_KEY=
DESK_API_KEY=4bc7d7ba4dc549fcb9fc2bab6aa6a15a
"@
Set-Content -Path $botEnv -Value $botContent -Encoding UTF8
Log "Synced bsv32-forward-bot.env"

# 2. Ensure Windows services
foreach ($svc in @("postgresql-x64-17", "Memurai")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s -and $s.Status -ne "Running") {
        Start-Service $svc
        Log "Started $svc"
    }
}

# 3. Start Bilshenz execution layer (MT5 :8765, desk :8791, forward worker)
$bStart = Join-Path $Bilshenz "deploy\windows\start-all-now.ps1"
if (Test-Path $bStart) {
    Log "Starting Bilshenz stack..."
    & $bStart -AppDir $Bilshenz 2>&1 | ForEach-Object { Log $_ }
} else {
    Log "WARN: Bilshenz start script missing"
}

Start-Sleep -Seconds 20

# 4. Start JCM platform (sidecars 8083/8084, API, scheduler, dashboard)
$platformStart = Join-Path $JcmRoot "scripts\start-platform.ps1"
if (Test-Path $platformStart) {
    Log "Starting JCM platform..."
    & $platformStart 2>&1 | ForEach-Object { Log $_ }
} else {
    Log "FAIL: start-platform.ps1 missing"
}

Start-Sleep -Seconds 15

# 5. Webhook smoke test
try {
    $py = Join-Path $JcmRoot "backend\.venv\Scripts\python.exe"
    $sample = Join-Path $JcmRoot "scripts\sample_event_ingest.py"
    if ((Test-Path $py) -and (Test-Path $sample)) {
        $env:EVENT_WEBHOOK_SECRET = "26nvWoyYBrR4GMuNZeaFLJP1OXc75Idi"
        $env:API_URL = "http://127.0.0.1:8000"
        $out = & $py $sample 2>&1
        Log "Webhook test: $out"
    }
} catch {
    Log "Webhook test FAIL: $($_.Exception.Message)"
}

# 6. Forward sidecar emit test
try {
    $fwdKey = "jcm_s930px6rvhanj7kt5qi8fy41ocdu"
    $body = '{"event_type":"trade_executed","use_sample":true}'
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8083/emit-event" -Method POST `
        -Headers @{ Authorization = "Bearer $fwdKey" } -Body $body -ContentType "application/json" -TimeoutSec 15
    Log "Forward emit: status=$($r.status_code)"
} catch {
    Log "Forward emit FAIL: $($_.Exception.Message)"
}

# 7. Remove Cursor completely
Log "Removing Cursor..."
Get-Process cursor -ErrorAction SilentlyContinue | Stop-Process -Force
$cursorPaths = @(
    "$env:LOCALAPPDATA\Programs\cursor",
    "$env:USERPROFILE\Desktop\Cursor.lnk",
    "$env:USERPROFILE\AppData\Roaming\Cursor",
    "$env:USERPROFILE\.cursor"
)
foreach ($p in $cursorPaths) {
    if (Test-Path $p) {
        try {
            Remove-Item -Recurse -Force $p -ErrorAction Stop
            Log "Removed $p"
        } catch {
            Log "Could not remove $p : $($_.Exception.Message)"
        }
    }
}
# Remove from PATH if present (user env)
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -match "cursor") {
    $newPath = ($userPath -split ';' | Where-Object { $_ -notmatch 'cursor' }) -join ';'
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Log "Cleaned Cursor from user PATH"
}

Start-Sleep -Seconds 5

# 8. Final health report
Log "=== FINAL HEALTH ==="
$checks = @(
    @{ Name = "JCM API"; Url = "http://127.0.0.1:8000/health" },
    @{ Name = "Dashboard"; Url = "http://127.0.0.1:3000" },
    @{ Name = "MT5"; Url = "http://127.0.0.1:8765/health" },
    @{ Name = "Desk"; Url = "http://127.0.0.1:8791/health" },
    @{ Name = "Forward"; Url = "http://127.0.0.1:8083/health"; H = @{ Authorization = "Bearer jcm_s930px6rvhanj7kt5qi8fy41ocdu" } },
    @{ Name = "Watchdog"; Url = "http://127.0.0.1:8084/health"; H = @{ Authorization = "Bearer jcm_caxs285n7flj0t4muord1z63hgbi" } }
)
foreach ($c in $checks) {
    try {
        $params = @{ Uri = $c.Url; UseBasicParsing = $true; TimeoutSec = 10 }
        if ($c.H) { $params.Headers = $c.H }
        $r = Invoke-WebRequest @params
        Log "$($c.Name): OK ($($r.StatusCode))"
    } catch {
        Log "$($c.Name): FAIL"
    }
}

try {
    $ov = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/overview" -TimeoutSec 10
    Log "Overview: bsv32=$($ov.bsv32_status) mt5=$($ov.mt5_connected) alerts=$($ov.active_alerts_count) infra=$($ov.infra_health_score)"
} catch {
    Log "Overview FAIL"
}

$os = Get-CimInstance Win32_OperatingSystem
$freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
Log "RAM free: ${freeGB}GB"
Log "Log saved: $LogFile"
Log "=== VPS FIX COMPLETE ==="
