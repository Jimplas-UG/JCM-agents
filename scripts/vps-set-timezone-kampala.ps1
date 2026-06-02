# Set VPS clock to East Africa (Kampala / Nairobi, UTC+3).
$ErrorActionPreference = "Stop"
$tzId = "E. Africa Standard Time"

Set-TimeZone -Id $tzId
tzutil /s $tzId

$tz = Get-TimeZone
$now = Get-Date
Write-Host "Timezone: $($tz.Id) ($($tz.DisplayName))"
Write-Host "Local time: $($now.ToString('yyyy-MM-dd HH:mm:ss'))"

# Re-register daily briefing at 09:00 local (Kampala)
& "$PSScriptRoot\vps-install-daily-briefing-task.ps1"
