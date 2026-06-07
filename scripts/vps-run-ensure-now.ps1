Copy-Item "C:\jcm-project\scripts\vps-ensure-forward-bot.ps1" "C:\jcm\scripts\" -Force
Copy-Item "C:\jcm-project\scripts\vps-tsx-worker.ps1" "C:\jcm\scripts\" -Force
& "C:\jcm\scripts\vps-ensure-forward-bot.ps1"
Get-Content "C:\Users\Administrator\ensure-forward.log" -Tail 15
