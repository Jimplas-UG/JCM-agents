$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -File C:\jcm\test-sidecar-system.ps1"
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName "SidecarSystemTest" -Action $action -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName "SidecarSystemTest"
Start-Sleep -Seconds 8
Get-Content C:\jcm\logs\sidecar-system-test.log -EA SilentlyContinue
netstat -ano | findstr ":8083"
