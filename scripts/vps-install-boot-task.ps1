# Run stack at boot as SYSTEM (survives SSH disconnect + no interactive session needed)
$ErrorActionPreference = "Stop"
$script = "C:\Users\Administrator\vps-direct-start.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "Bilshenz-DirectStart" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force
Write-Host "Registered Bilshenz-DirectStart at boot"
schtasks /Run /TN "Bilshenz-DirectStart"
Write-Host "Triggered Bilshenz-DirectStart now"
