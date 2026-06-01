$ErrorActionPreference = "Continue"
Write-Host "=== JCM VPS status ===" -ForegroundColor Cyan

try {
    $h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 12
    Write-Host "API: $($h.status) db=$($h.database) redis=$($h.redis)"
} catch { Write-Host "API FAIL: $_" -ForegroundColor Red }

$sched = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "agent_scheduler|jcm-scheduler-keepalive"
}
Write-Host "Agent scheduler: $(if ($sched) { 'RUNNING PID ' + $sched.ProcessId } else { 'NOT RUNNING' })"

$fwd = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match "run-forward-demo" }
Write-Host "Forward bot: $(if ($fwd) { 'RUNNING' } else { 'NOT RUNNING' })"

$log = "C:\opt\bilshenz\backend\validation\data\forward-demo-log.jsonl"
if (Test-Path $log) {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $rejects = 0; $fills = 0
    Get-Content $log -Tail 3000 -EA SilentlyContinue | ForEach-Object {
        if ($_ -notmatch $today) { return }
        if ($_ -match "ORDER_REJECTED") { $rejects++ }
        if ($_ -match "ORDER_FILL") { $fills++ }
    }
    Write-Host "Forward log today: fills=$fills rejects=$rejects"
}

$wl = "C:\logs\tradingbot\watchdog.log"
if (Test-Path $wl) {
    Write-Host "Watchdog tail:"
    Get-Content $wl -Tail 3 | ForEach-Object { Write-Host "  $_" }
}

$tok = $false; $chat = $false
$envPath = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env"
if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^\s*TELEGRAM_BOT_TOKEN=(.+)$' -and $Matches[1].Trim()) { $tok = $true }
        if ($_ -match '^\s*TELEGRAM_CHAT_ID=(.+)$' -and $Matches[1].Trim()) { $chat = $true }
    }
}
Write-Host "Telegram configured: $(if ($tok -and $chat) { 'YES' } else { 'NO — 09:00 CEO alert will not send' })"

$eb = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\app\services\executive_briefing\service.py"
Write-Host "Executive briefing module: $(if (Test-Path $eb) { 'deployed' } else { 'MISSING' })"
