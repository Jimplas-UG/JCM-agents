# Finish Cursor removal + forward emit test + final audit
$ErrorActionPreference = "Continue"

Write-Host "=== Cursor cleanup ==="
Get-Process cursor -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
$remaining = @(
    "$env:LOCALAPPDATA\Programs\cursor",
    "$env:USERPROFILE\AppData\Roaming\Cursor",
    "$env:USERPROFILE\Desktop\Cursor.lnk",
    "$env:USERPROFILE\.cursor"
)
foreach ($p in $remaining) {
    if (Test-Path $p) {
        Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue
        if (Test-Path $p) { Write-Host "STILL EXISTS: $p" } else { Write-Host "Removed: $p" }
    } else {
        Write-Host "Gone: $p"
    }
}

Write-Host "`n=== Forward emit test ==="
try {
    $body = '{"event_type":"trade_executed","use_sample":true}'
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:8083/emit-event" -Method POST `
        -Headers @{ Authorization = "Bearer jcm_s930px6rvhanj7kt5qi8fy41ocdu" } -Body $body -ContentType "application/json"
    Write-Host "Emit status: $($r.status_code) event recorded"
} catch { Write-Host "Emit FAIL: $($_.Exception.Message)" }

Write-Host "`n=== Watchdog metrics ==="
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8084/vps/metrics" -Headers @{ Authorization = "Bearer jcm_caxs285n7flj0t4muord1z63hgbi" }
    Write-Host "CPU=$($m.cpu_pct)% RAM=$($m.ram_pct)% Disk=$($m.disk_pct)%"
} catch { Write-Host "Metrics FAIL" }

Write-Host "`n=== Dashboard overview ==="
$ov = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/overview"
Write-Host "bsv32=$($ov.bsv32_status) mt5=$($ov.mt5_connected) infra=$($ov.infra_health_score) alerts=$($ov.active_alerts_count)"

Write-Host "`n=== Marketing cycle ==="
try {
    $mc = Invoke-RestMethod -Method POST "http://127.0.0.1:8000/marketing/cycle" -TimeoutSec 30
    Write-Host "Marketing cycle OK"
} catch { Write-Host "Marketing: $($_.Exception.Message)" }

$os = Get-CimInstance Win32_OperatingSystem
Write-Host "`nRAM free: $([math]::Round($os.FreePhysicalMemory/1MB,2))GB / $([math]::Round($os.TotalVisibleMemorySize/1MB,2))GB"
