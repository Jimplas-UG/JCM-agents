# Keepalive: restart any down service every 60s (never kills running processes)
$ErrorActionPreference = "Continue"
& "C:\Users\Administrator\vps-write-short-scripts.ps1" -EA SilentlyContinue

function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }
function Ensure([string]$name, [string]$script, [int]$port) {
    if (PortUp $port) { return }
    Write-Host "[$(Get-Date -Format HH:mm:ss)] RESTART $name :$port down"
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$script -WindowStyle Hidden
}

$LogFile = "C:\jcm\keepalive.log"
while ($true) {
    Ensure "MT5" "C:\jcm\run-mt5.ps1" 8765
    Ensure "Dashboard" "C:\jcm\run-dashboard.ps1" 3000
    if (-not (PortUp 8083)) {
        Ensure "Sidecars" "C:\jcm\run-sidecars.ps1" 8083
    }
    if (-not (PortUp 8000)) {
        Ensure "API" "C:\jcm\run-api.ps1" 8000
    }
    if (-not (Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'run-forward-demo' })) {
        & "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
    }
    Start-Sleep -Seconds 60
}
