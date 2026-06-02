# From dev machine: install JCMAPI NSSM service on VPS.
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script = Join-Path $Repo "scripts\vps-install-api-nssm.ps1"
scp $script jcm-vps:C:/Users/Administrator/vps-install-api-nssm.ps1
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-install-api-nssm.ps1"
