# Backup: send briefing only if today's Telegram delivery was not recorded.
$ErrorActionPreference = "Stop"
$LogDir = "C:\logs\jcm"
$LogFile = Join-Path $LogDir "daily-briefing-telegram.log"
function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [backup] $msg"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

$Root = "C:\jcm-project"
if (-not (Test-Path "$Root\backend\.venv\Scripts\python.exe")) {
    $Root = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
}
$Backend = "$Root\backend"
$Py = "$Backend\.venv\Scripts\python.exe"
Copy-Item "$Root\.env" "$Backend\.env" -Force
Set-Location $Backend
Write-Log "daily_briefing_job --ensure"
& $Py -m app.workers.daily_briefing_job --ensure
exit $LASTEXITCODE
