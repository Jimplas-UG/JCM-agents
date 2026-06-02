# From dev machine: ensure agent scheduler watchdog on VPS.
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$watchdog = Join-Path $Repo "scripts\vps-scheduler-watchdog.ps1"
scp $watchdog jcm-vps:C:/Users/Administrator/jcm-scheduler-watchdog.ps1
scp (Join-Path $Repo "backend\app\workers\agent_scheduler.py") jcm-vps:C:/jcm-project/backend/app/workers/agent_scheduler.py

scp (Join-Path $Repo "scripts\vps-install-scheduler-watchdog-task.ps1") jcm-vps:C:/Users/Administrator/vps-install-scheduler-watchdog-task.ps1
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-install-scheduler-watchdog-task.ps1"
