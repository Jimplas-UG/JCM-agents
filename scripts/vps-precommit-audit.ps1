# Pre-commit audit: forward alignment + institutional readiness + pytest.
$ErrorActionPreference = "Continue"
$fail = 0

Write-Host "=== PRE-COMMIT AUDIT $(Get-Date -Format 'yyyy-MM-dd HH:mm') ===" -ForegroundColor Cyan

# 1. Start forward bot if down (sync launcher from jcm-project first)
$repoLauncher = "C:\jcm-project\run-forward-bot.vps.ps1"
$fwdLauncher = "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
if (Test-Path $repoLauncher) {
    Copy-Item $repoLauncher $fwdLauncher -Force
}
if (Test-Path $fwdLauncher) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $fwdLauncher
    Start-Sleep -Seconds 30
}

# 2. Forward alignment audit
& powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-audit-forward-alignment.ps1
if ($LASTEXITCODE -ne 0) { $fail++ }

# 3. Institutional readiness
Set-Location C:\opt\bilshenz\backend
$env:INST_INFRA_SCORE = "95"
& npx tsx scripts/run-institutional-readiness.ts --infra-score=95
$readyScore = $LASTEXITCODE
if ($readyScore -ne 0) {
    Write-Host "WARN institutional readiness below 80" -ForegroundColor Yellow
}

# 4. JCM pytest
$py = "C:\jcm-project\backend\.venv\Scripts\python.exe"
if (Test-Path $py) {
    Set-Location C:\jcm-project\backend
    $env:PYTHONPATH = "C:\jcm-project\backend"
    & $py -m pip install pytest -q 2>$null
    & $py -m pytest tests/ -q --tb=line
    if ($LASTEXITCODE -ne 0) { $fail++ }
} else {
    Write-Host "WARN pytest skipped - no venv" -ForegroundColor Yellow
}

# 5. Reconcile trades (non-fatal on stale records)
Set-Location C:\jcm-project\backend
if (Test-Path $py) {
    & $py -m app.scripts.reconcile_trades
}

# 6. Institutional API module smoke test
if (Test-Path $py) {
    & $py -c "from app.services.institutional_readiness import build_institutional_readiness_payload; print('institutional_readiness import OK')"
    if ($LASTEXITCODE -ne 0) { $fail++ }
}

Write-Host "=== PRE-COMMIT RESULT: fail_count=$fail readiness_exit=$readyScore ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
exit $(if ($fail -gt 0) { 1 } else { 0 })
