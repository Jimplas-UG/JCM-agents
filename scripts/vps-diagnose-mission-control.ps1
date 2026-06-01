$ErrorActionPreference = "Continue"
$mc = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\app\static\mission-control.html"
Write-Host "=== mission-control.html ==="
if (Test-Path $mc) {
    $f = Get-Item $mc
    Write-Host "Size: $($f.Length) bytes Modified: $($f.LastWriteTime)"
    $head = Get-Content $mc -TotalCount 3
    $head | ForEach-Object { Write-Host $_ }
} else {
    Write-Host "MISSING: $mc"
}
Write-Host "`n=== API local ==="
try {
    $h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 10
    Write-Host "health: $($h.status)"
} catch { Write-Host "health FAIL: $_" }
try {
    $o = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/overview" -TimeoutSec 10
    Write-Host "overview open_positions: $($o.open_positions)"
} catch { Write-Host "overview FAIL: $_" }
try {
    $b = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/briefing" -TimeoutSec 10
    Write-Host "briefing date: $($b.briefing_date)"
} catch { Write-Host "briefing FAIL: $_" }
$proc = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match "uvicorn|app.main" }
Write-Host "`nAPI processes: $($proc.Count)"
