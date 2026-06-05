# On VPS boot: if past 09:00 local and briefing not sent today, deliver (--ensure).
$ErrorActionPreference = "Stop"
. "C:\jcm\scripts\vps-briefing-common.ps1"
$hour = (Get-Date).Hour
if ($hour -lt 9) {
    Write-JcmBriefingLog "startup catchup skipped (before 09:00)" "boot"
    exit 0
}
Initialize-JcmBriefingRuntime
Write-JcmBriefingLog "startup catchup --ensure" "boot"
& $script:JcmBriefingPy -m app.workers.daily_briefing_job --ensure
exit $LASTEXITCODE
