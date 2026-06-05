# Allocator pipeline: backfill, reconcile, tear sheet, readiness gates.
$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "=== ALLOCATOR PIPELINE $stamp ===" -ForegroundColor Cyan

# 1. MT5 must be up for backfill
try {
    $st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 10
    if (-not $st.connected) { throw "MT5 down" }
} catch {
    Write-Host "WARN: MT5 not connected - backfill may skip deals" -ForegroundColor Yellow
}

# 2. JCM backfill + reconcile + tear sheet
$py = "C:\jcm-project\backend\.venv\Scripts\python.exe"
$backend = "C:\jcm-project\backend"
if (Test-Path $py) {
    Copy-Item "C:\jcm-project\.env" "$backend\.env" -Force
    Set-Location $backend
    $env:PYTHONPATH = $backend
    & $py -m app.scripts.run_allocator_pipeline
}

# 3. Restart JCMAPI to pick up new endpoints
C:\jcm\nssm\nssm.exe restart JCMAPI confirm 2>$null | Out-Null
Start-Sleep -Seconds 12

# 4. Allocator readiness gates (Bilshenz)
$bilshenz = "C:\opt\bilshenz\backend"
Set-Location $bilshenz
$env:KILL_SWITCH_ENFORCED = "1"
$env:INST_INFRA_SCORE = "95"
& node "node_modules\tsx\dist\cli.mjs" scripts/run-allocator-readiness.ts
$gateExit = $LASTEXITCODE

Write-Host ""
if ($gateExit -eq 0) {
    Write-Host "ALLOCATOR CHECK-READY: YES" -ForegroundColor Green
} else {
    Write-Host "ALLOCATOR CHECK-READY: NO (see blockers in report)" -ForegroundColor Yellow
    Get-Content "validation\data\allocator-readiness-report.txt" -ErrorAction SilentlyContinue | Select-String "FAIL|Blockers|milestones" | ForEach-Object { $_.Line }
}

exit $gateExit
