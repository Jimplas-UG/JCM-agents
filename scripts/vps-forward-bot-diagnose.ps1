# Forward bot + execution stack diagnosis (read-only, no kills)
$ErrorActionPreference = "Continue"
$LogDir = "C:\logs\tradingbot"
$Bilshenz = "C:\opt\bilshenz"

Write-Host "=== FORWARD BOT DIAGNOSIS $(Get-Date -Format o) ===" -ForegroundColor Cyan

Write-Host "`n--- Scheduled tasks ---"
foreach ($tn in @("Bilshenz-MT5-API","Bilshenz-DeskAPI","Bilshenz-ForwardBot","Bilshenz-Watchdog","JCM-Stack-Watchdog","JCM-Stack-Startup")) {
    $t = schtasks /Query /TN $tn /FO LIST 2>$null
    if ($t) {
        $st = ($t | Select-String "Status:" | Select-Object -First 1).ToString().Trim()
        $last = ($t | Select-String "Last Run Time:" | Select-Object -First 1)
        Write-Host "$tn : $st $(if ($last) { $last.ToString().Trim() })"
    } else {
        Write-Host "$tn : NOT REGISTERED"
    }
}

Write-Host "`n--- Ports ---"
foreach ($p in 8765,8791,8000,3000,8083,8084) {
    $l = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-Host ":$p $(if ($l) { "LISTEN PID $($l.OwningProcess)" } else { "DOWN" })"
}

Write-Host "`n--- Forward bot process ---"
$fwdProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
}
if ($fwdProcs) {
    $fwdProcs | ForEach-Object { Write-Host "PID $($_.ProcessId) $($_.CommandLine.Substring(0,[Math]::Min(120,$_.CommandLine.Length)))" }
} else {
    Write-Host "NO forward-demo process running"
}

Write-Host "`n--- MT5 health ---"
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 8
    Write-Host "MT5 connected=$($m.connected) trade_allowed=$($m.trade_allowed)"
} catch { Write-Host "MT5 FAIL: $($_.Exception.Message)" }

Write-Host "`n--- Desk health ---"
try {
    $d = Invoke-RestMethod "http://127.0.0.1:8791/health" -TimeoutSec 8
    Write-Host "Desk ok=$($d.ok)"
} catch { Write-Host "Desk FAIL: $($_.Exception.Message)" }

Write-Host "`n--- Safety state ---"
$safety = "C:\logs\tradingbot\safety-state.json"
if (Test-Path $safety) {
    Get-Content $safety -Raw
} else { Write-Host "safety-state.json missing" }

Write-Host "`n--- tradingbot.env (non-secret keys) ---"
$ef = "C:\ProgramData\Bilshenz\tradingbot.env"
if (Test-Path $ef) {
    Get-Content $ef | Where-Object { $_ -notmatch 'KEY|SECRET|PASSWORD' -and $_ -match '\S' }
}

Write-Host "`n--- forward-bot.log (last 40 lines) ---"
$fl = Join-Path $LogDir "forward-bot.log"
if (Test-Path $fl) { Get-Content $fl -Tail 40 } else { Write-Host "missing $fl" }

Write-Host "`n--- watchdog.log (last 25 lines) ---"
$wl = Join-Path $LogDir "watchdog.log"
if (Test-Path $wl) { Get-Content $wl -Tail 25 } else { Write-Host "missing $wl" }

Write-Host "`n--- reconnect.jsonl (last 10) ---"
$rc = Join-Path $LogDir "reconnect.jsonl"
if (Test-Path $rc) { Get-Content $rc -Tail 10 }

Write-Host "`n--- RAM ---"
$os = Get-CimInstance Win32_OperatingSystem
Write-Host "Free $([math]::Round($os.FreePhysicalMemory/1MB,2))GB / $([math]::Round($os.TotalVisibleMemorySize/1MB,2))GB"
