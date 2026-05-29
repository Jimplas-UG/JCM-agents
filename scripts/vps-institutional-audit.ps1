# Final institutional audit — ensure stack up, then verify all endpoints
$ErrorActionPreference = "Continue"
$ApiKey = "MlxG1e0W5D2fTQsAJEwdCmyFKYVrOb3qz4nphk7HR98ZaUvo"
$FwdKey = "jcm_s930px6rvhanj7kt5qi8fy41ocdu"
$WdKey = "jcm_caxs285n7flj0t4muord1z63hgbi"

Write-Host "=== ENSURE STACK ==="
& "C:\Users\Administrator\start-sidecars.ps1"
if (-not (Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue)) {
    & "C:\Users\Administrator\vps-start-dashboard.ps1"
}
Start-Sleep -Seconds 5
Write-Host "`n=== CURSOR PURGE ==="
Get-Process cursor -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
foreach ($p in @(
    "$env:LOCALAPPDATA\Programs\cursor",
    "$env:USERPROFILE\AppData\Roaming\Cursor",
    "$env:USERPROFILE\Desktop\Cursor.lnk",
    "$env:USERPROFILE\.cursor"
)) {
    if (Test-Path $p) {
        Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue
        Write-Host "$(if (Test-Path $p) {'STILL'} else {'OK'}) $p"
    } else { Write-Host "OK gone $p" }
}

Write-Host "`n=== SCHEDULED TASKS (Bilshenz) ==="
schtasks /Query /TN "Bilshenz-Watchdog" /FO LIST 2>$null | Select-String "Status|Task Name"
schtasks /Query /TN "Bilshenz-ForwardBot" /FO LIST 2>$null | Select-String "Status|Task Name"

Write-Host "`n=== ENDPOINT AUDIT ==="
$checks = @(
    @{N="JCM API"; U="http://127.0.0.1:8000/health"},
    @{N="Dashboard"; U="http://127.0.0.1:3000"},
    @{N="MT5"; U="http://127.0.0.1:8765/health"},
    @{N="Desk"; U="http://127.0.0.1:8791/health"},
    @{N="Forward sidecar"; U="http://127.0.0.1:8083/health"; H=@{Authorization="Bearer $FwdKey"}},
    @{N="Watchdog sidecar"; U="http://127.0.0.1:8084/health"; H=@{Authorization="Bearer $WdKey"}},
    @{N="Watchdog metrics"; U="http://127.0.0.1:8084/vps/metrics"; H=@{Authorization="Bearer $WdKey"}}
)
$pass = 0; $fail = 0
foreach ($c in $checks) {
    try {
        $params = @{Uri=$c.U; UseBasicParsing=$true; TimeoutSec=10}
        if ($c.H) { $params.Headers = $c.H }
        $r = Invoke-WebRequest @params
        Write-Host "PASS $($c.N) $($r.StatusCode)"
        $pass++
    } catch {
        Write-Host "FAIL $($c.N)"
        $fail++
    }
}

Write-Host "`n=== WEBHOOK INGEST ==="
try {
    $py = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\.venv\Scripts\python.exe"
    $sample = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\scripts\sample_event_ingest.py"
    $env:EVENT_WEBHOOK_SECRET = "26nvWoyYBrR4GMuNZeaFLJP1OXc75Idi"
    $env:API_URL = "http://127.0.0.1:8000"
    $out = & $py $sample 2>&1
    if ($out -match "200") { Write-Host "PASS webhook $out"; $pass++ }
    else { Write-Host "FAIL webhook $out"; $fail++ }
} catch { Write-Host "FAIL webhook"; $fail++ }

Write-Host "`n=== FORWARD EMIT ==="
try {
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8083/emit-event" -Method POST `
        -Headers @{Authorization="Bearer $FwdKey"} -Body '{"event_type":"trade_executed","use_sample":true}' -ContentType "application/json"
    Write-Host "PASS forward emit status=$($r.status_code)"
    $pass++
} catch { Write-Host "FAIL forward emit"; $fail++ }

Write-Host "`n=== MARKETING CYCLE ==="
try {
    $r = Invoke-RestMethod -Method POST "http://127.0.0.1:8000/marketing/cycle" -Headers @{"X-API-Key"=$ApiKey} -TimeoutSec 60
    Write-Host "PASS marketing cycle"
    $pass++
} catch { Write-Host "FAIL marketing: $($_.Exception.Message)"; $fail++ }

Write-Host "`n=== PLATFORM OVERVIEW ==="
$ov = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/overview" -Headers @{"X-API-Key"=$ApiKey} -ErrorAction SilentlyContinue
if (-not $ov) { $ov = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/overview" }
Write-Host "bsv32=$($ov.bsv32_status) mt5=$($ov.mt5_connected) infra=$($ov.infra_health_score) alerts=$($ov.active_alerts_count)"

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "`nRAM: $([math]::Round($os.FreePhysicalMemory/1MB,2))GB free / $([math]::Round($os.TotalVisibleMemorySize/1MB,2))GB total"
Write-Host "AUDIT: $pass passed, $fail failed"
