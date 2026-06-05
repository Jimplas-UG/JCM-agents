# Primary: executive briefing + Telegram (09:00 daily).
$ErrorActionPreference = "Stop"
$common = Join-Path $PSScriptRoot "vps-briefing-common.ps1"
if (-not (Test-Path $common)) { $common = "C:\jcm\scripts\vps-briefing-common.ps1" }
. $common
Initialize-JcmBriefingRuntime
Write-JcmBriefingLog "daily_briefing_job --force" "primary"
& $script:JcmBriefingPy -m app.workers.daily_briefing_job --force
$code = $LASTEXITCODE
if ($code -eq 0) { Write-JcmBriefingLog "SUCCESS: briefing pipeline completed" "primary" }
else { Write-JcmBriefingLog "ERROR: exit $code" "primary" }
exit $code
