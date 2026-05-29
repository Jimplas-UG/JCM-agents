# Start blocking service scripts in child PowerShell (survives SSH exit)
$ErrorActionPreference = "Continue"
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"

function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }
function Start-Blocking([string]$name, [string]$script, [string[]]$extra) {
    if ($name -eq "MT5" -and (PortUp 8765)) { Write-Host "MT5 already up"; return }
    if ($name -eq "Desk" -and (PortUp 8791)) { Write-Host "Desk already up"; return }
    if ($name -eq "API" -and (PortUp 8000)) { Write-Host "JCM API already up"; return }
    if ($name -eq "Dash" -and (PortUp 3000)) { Write-Host "Dashboard already up"; return }
    $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$script) + $extra
    Start-Process powershell.exe -ArgumentList $args -WindowStyle Hidden
    Write-Host "Started $name blocking wrapper"
}

$term = "C:\Program Files\MetaTrader 5 Exness\terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -EA SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"; Start-Sleep 15
}

Start-Blocking "MT5" "C:\opt\bilshenz\deploy\windows\run-mt5-api.ps1" @("-AppDir","C:\opt\bilshenz")
Start-Sleep 20
Start-Blocking "Desk" "C:\opt\bilshenz\deploy\windows\run-desk-api.ps1" @("-AppDir","C:\opt\bilshenz")
Start-Sleep 12
Start-Blocking "API" "$Jcm\scripts\run-jcm-api.ps1" @()
Start-Sleep 10
Start-Blocking "Dash" "$Jcm\scripts\run-jcm-dashboard.ps1" @()
Start-Sleep 10
& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
Start-Sleep 8
if (-not (PortUp 8083)) {
    Start-Blocking "Sidecars" "$Jcm\scripts\run-jcm-sidecars.ps1" @()
}
Start-Sleep 15
& "C:\Users\Administrator\vps-live-test.ps1"
