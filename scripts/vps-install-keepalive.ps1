$ErrorActionPreference = "Stop"
schtasks /End /TN "JCM-Keepalive" 2>$null
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-keepalive.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName "JCM-Keepalive" -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\Users\Administrator\vps-keepalive.ps1" -WindowStyle Hidden
Start-Sleep 3
& "C:\Users\Administrator\vps-start-all.ps1"
