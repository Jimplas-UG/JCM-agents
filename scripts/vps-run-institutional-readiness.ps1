# Generate institutional readiness report on VPS (target 80/100).
$ErrorActionPreference = "Stop"
$Backend = "C:\opt\bilshenz\backend"
Set-Location $Backend

$infraScore = 68
try {
    $audit = & powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-audit-forward-alignment.ps1 2>&1 | Out-String
    if ($audit -match 'PASS=(\d+)') {
        $pass = [int]$Matches[1]
        $infraScore = [math]::Min(95, [math]::Round(($pass / 21) * 100))
    }
} catch { }

Write-Host "Running institutional readiness (infra-score=$infraScore)..." -ForegroundColor Cyan
$env:INST_INFRA_SCORE = "$infraScore"
& npx tsx scripts/run-institutional-readiness.ts --infra-score=$infraScore
if ($LASTEXITCODE -ne 0) {
    Write-Host "Score below 80 - see report for targets" -ForegroundColor Yellow
}

$jcmBackend = "C:\jcm-project\backend"
$py = Join-Path $jcmBackend ".venv\Scripts\python.exe"
if (Test-Path $py) {
    Copy-Item "C:\jcm-project\.env" (Join-Path $jcmBackend ".env") -Force
    Set-Location $jcmBackend
    $env:PYTHONPATH = $jcmBackend
    & $py -m app.scripts.reconcile_trades
}
