$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
scp (Join-Path $Repo "scripts\vps-send-briefing-telegram.ps1") jcm-vps:C:/Users/Administrator/vps-send-briefing-telegram.ps1
scp (Join-Path $Repo "scripts\vps-install-daily-briefing-task.ps1") jcm-vps:C:/Users/Administrator/vps-install-daily-briefing-task.ps1
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-install-daily-briefing-task.ps1"
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-send-briefing-telegram.ps1"
