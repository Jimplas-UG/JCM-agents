# Audit all 9 JCM agents vs Mission Control data freshness (run on VPS).
# Usage: powershell -File C:\jcm-project\scripts\vps-audit-agents-mission-control.ps1
$ErrorActionPreference = "Continue"
$Base = "http://127.0.0.1:8000"
$Jcm = "C:\jcm-project"
$envFile = Join-Path $Jcm "backend\.env"
if (-not (Test-Path $envFile)) { $envFile = Join-Path $Jcm ".env" }

function Get-ApiKey {
    if (-not (Test-Path $envFile)) { return $null }
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*API_SECRET_KEY\s*=\s*(.+)$') { return $Matches[1].Trim().Trim('"') }
    }
    return $null
}

function Get-Json($path) {
    try {
        return Invoke-RestMethod "$Base$path" -TimeoutSec 15
    } catch {
        return @{ _error = $_.Exception.Message }
    }
}

Write-Host "=== JCM 9-Agent Mission Control Audit ===" -ForegroundColor Cyan
Write-Host "Time: $(Get-Date -Format o)"

# Scheduler process
$sched = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "agent_scheduler"
}
Write-Host "`n[Scheduler] agent_scheduler processes: $($sched.Count)"
if ($sched) { $sched | ForEach-Object { Write-Host "  PID $($_.ProcessId)" } }

$task = Get-ScheduledTask -TaskName "JCM-Agents-Sys" -EA SilentlyContinue
if ($task) {
    $info = Get-ScheduledTaskInfo -TaskName "JCM-Agents-Sys"
    Write-Host "[Task] JCM-Agents-Sys State=$($task.State) LastResult=$($info.LastTaskResult) LastRun=$($info.LastRunTime)"
}

$health = Get-Json "/health"
Write-Host "`n[API] status=$($health.status) db=$($health.database) redis=$($health.redis) agents_registered=$($health.registered_agents)"

$overview = Get-Json "/dashboard/overview"
Write-Host "`n[1 CEO Copilot] overview last_updated=$($overview.last_updated) infra_score=$($overview.infra_health_score) alerts=$($overview.active_alerts) marketing_drafts=$($overview.pending_marketing_drafts)"

$infra = Get-Json "/dashboard/infrastructure"
$ih = $infra.current
Write-Host "[2 Infra Resilience] healthy=$($ih.healthy) mt5=$($ih.mt5_connected) forward=$($ih.services.forward_bot.ok)"

$risk = Get-Json "/dashboard/risk"
Write-Host "[3 Portfolio Risk] score=$($risk.risk_score) open_positions=$($risk.open_positions)"

$exec = Get-Json "/dashboard/execution-quality"
Write-Host "[4 Execution Quality] sample=$($exec.sample_size) rejection_rate=$($exec.rejection_rate)"

$perf = Get-Json "/dashboard/performance"
if ($null -eq $perf -or $perf._error) {
    Write-Host "[5 Performance Intel] NO daily report for today" -ForegroundColor Yellow
} else {
    Write-Host "[5 Performance Intel] report_date=$($perf.report_date) win_rate=$($perf.win_rate)"
}

$trades = Get-Json "/dashboard/trades?limit=1"
if ($trades -is [array] -and $trades.Count -gt 0) {
    Write-Host "[6 Quant Memory] latest trade $($trades[0].created_at) outcome=$($trades[0].outcome)"
} else {
    Write-Host "[6 Quant Memory] no trades" -ForegroundColor Yellow
}

$audit = Get-Json "/dashboard/audit?limit=1"
if ($audit -is [array] -and $audit.Count -gt 0) {
    Write-Host "[7 Explainability] latest audit $($audit[0].created_at)"
} else {
    Write-Host "[7 Explainability] no audits" -ForegroundColor Yellow
}

$research = Get-Json "/dashboard/research?status=pending"
$rc = if ($research -is [array]) { $research.Count } else { 0 }
Write-Host "[8 Research Evolution] pending findings=$rc"

$mstats = Get-Json "/marketing/stats"
Write-Host "[9 Marketing] drafts=$($mstats.draft_count) approved=$($mstats.approved_count)"

$drafts = Get-Json "/marketing/queue?status=draft&limit=1"
if ($drafts -is [array] -and $drafts.Count -gt 0) {
    Write-Host "    newest draft created_at=$($drafts[0].created_at)"
}

$alerts = Get-Json "/dashboard/alerts?limit=1"
if ($alerts -is [array] -and $alerts.Count -gt 0) {
    Write-Host "`n[Alerts] newest unacked: $($alerts[0].created_at) - $($alerts[0].title)" -ForegroundColor Yellow
}

Write-Host "`n=== Done ===" -ForegroundColor Green
