Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\jcm\run-sidecar-fwd.ps1" -WindowStyle Hidden
Start-Sleep -Seconds 6
Get-NetTCPConnection -LocalPort 8083 -State Listen -EA SilentlyContinue | Format-Table LocalPort,OwningProcess
