# From dev machine: ensure persistent agent scheduler on VPS (09:00 CEO briefing).
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
& (Join-Path $Repo "scripts\vps-ensure-agent-scheduler.ps1")
