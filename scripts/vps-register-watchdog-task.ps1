# Register JCM watchdog + boot startup tasks
$ErrorActionPreference = "Stop"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

$watchdog = "JCM-Stack-Watchdog"
$wdAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-watchdog.ps1"
$wdTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
Register-ScheduledTask -TaskName $watchdog -Action $wdAction -Trigger $wdTrigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "OK $watchdog every 5 min"

$boot = "JCM-Stack-Startup"
$bootAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-restart-all.ps1"
$bootTrigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName $boot -Action $bootAction -Trigger $bootTrigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Host "OK $boot at startup"
