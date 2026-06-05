# Backup: send only if today's Telegram delivery not recorded (09:15 daily).
$ErrorActionPreference = "Stop"
$common = Join-Path $PSScriptRoot "vps-briefing-common.ps1"
if (-not (Test-Path $common)) { $common = "C:\jcm\scripts\vps-briefing-common.ps1" }
. $common
Initialize-JcmBriefingRuntime
Write-JcmBriefingLog "daily_briefing_job --ensure" "backup"
& $script:JcmBriefingPy -m app.workers.daily_briefing_job --ensure
$code = $LASTEXITCODE
if ($code -eq 0) { Write-JcmBriefingLog "SUCCESS: backup completed" "backup" }
else { Write-JcmBriefingLog "ERROR: exit $code" "backup" }
exit $code
