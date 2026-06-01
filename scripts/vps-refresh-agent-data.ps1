# Run one cycle for stale agents + acknowledge obsolete infra alerts (VPS).
$ErrorActionPreference = "Continue"
$Base = "http://127.0.0.1:8000"
$Jcm = "C:\jcm-project"
$envFile = Join-Path $Jcm "backend\.env"
if (-not (Test-Path $envFile)) { $envFile = Join-Path $Jcm ".env" }

$key = $null
foreach ($line in Get-Content $envFile -EA SilentlyContinue) {
    if ($line -match '^\s*API_SECRET_KEY\s*=\s*(.+)$') { $key = $Matches[1].Trim().Trim('"'); break }
}
if (-not $key) { Write-Host "FAIL: API_SECRET_KEY not in .env"; exit 1 }
$headers = @{ "X-API-Key" = $key }

Write-Host "=== Refresh agent data ===" -ForegroundColor Cyan

foreach ($agent in @(
    "infra_resilience", "portfolio_risk", "execution_quality",
    "performance_intel", "quant_memory", "explainability",
    "research_evolution", "ceo_copilot", "marketing_agent"
)) {
    try {
        $r = Invoke-RestMethod -Method POST -Uri "$Base/agents/$agent/run" -Headers $headers -TimeoutSec 120
        Write-Host "OK $agent -> $($r.status)"
    } catch {
        Write-Host "FAIL $agent -> $($_.Exception.Message)" -ForegroundColor Red
    }
}

try {
    $r = Invoke-RestMethod -Method POST -Uri "$Base/marketing/cycle" -Headers $headers -TimeoutSec 120
    Write-Host "OK marketing/cycle items=$($r.items_generated) trends=$($r.trends_scanned)"
} catch {
    Write-Host "marketing/cycle: $($_.Exception.Message)"
}

try {
    $r = Invoke-RestMethod -Method POST -Uri "$Base/dashboard/performance/generate" -Headers $headers -TimeoutSec 120
    Write-Host "OK performance/generate"
} catch {
    Write-Host "performance/generate: $($_.Exception.Message)"
}

# Ack stale infra alerts from May 29 outage (services recovered)
try {
    $totalAck = 0
    for ($i = 0; $i -lt 20; $i++) {
        $alerts = Invoke-RestMethod "$Base/dashboard/alerts?acknowledged=false&limit=50" -TimeoutSec 30
        if (-not $alerts -or $alerts.Count -eq 0) { break }
        $stale = @($alerts | Where-Object {
            $_.agent_source -eq "infra_resilience" -and $_.title -match "Infrastructure Degradation"
        })
        if ($stale.Count -eq 0) { break }
        foreach ($a in $stale) {
            Invoke-RestMethod -Method POST -Uri "$Base/dashboard/alerts/$($a.id)/acknowledge" -Headers $headers -TimeoutSec 15 | Out-Null
            $totalAck++
        }
    }
    Write-Host "Acknowledged $totalAck stale infra alerts"
} catch {
    Write-Host "alert ack: $($_.Exception.Message)"
}

Write-Host "=== Done ===" -ForegroundColor Green
