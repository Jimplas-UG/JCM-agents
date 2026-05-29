# Install NSSM + Windows services for MT5 API, Dashboard, Keepalive (Administrator, auto-restart)
$ErrorActionPreference = "Stop"
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$NssmDir = "C:\jcm\nssm"
$NssmExe = "$NssmDir\nssm.exe"

Write-Host "=== NSSM SERVICE INSTALL ===" -ForegroundColor Cyan

# --- Prepare C:\jcm launchers ---
New-Item -ItemType Directory -Force -Path C:\jcm, $NssmDir | Out-Null
& "C:\Users\Administrator\vps-write-short-scripts.ps1" -ErrorAction SilentlyContinue
if (-not (Test-Path "C:\jcm\run-mt5.ps1")) {
    & "$PSScriptRoot\vps-write-short-scripts.ps1" -ErrorAction SilentlyContinue
}

# --- Download NSSM if missing ---
if (-not (Test-Path $NssmExe)) {
    Write-Host "Downloading NSSM..."
    $zip = "$env:TEMP\nssm.zip"
    Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
    Copy-Item "$env:TEMP\nssm-2.24\win64\nssm.exe" $NssmExe -Force
    Write-Host "NSSM installed to $NssmExe"
}

function Remove-NssmService([string]$name) {
    $existing = Get-Service $name -ErrorAction SilentlyContinue
    if ($existing) {
        & $NssmExe stop $name confirm 2>$null
        Start-Sleep -Seconds 2
        & $NssmExe remove $name confirm 2>$null
        Start-Sleep -Seconds 1
        Write-Host "Removed old service $name"
    }
}

function Install-NssmService([string]$name, [string]$exe, [string]$appParams, [string]$dir, [string]$logName) {
    Remove-NssmService $name
    & $NssmExe install $name $exe
    & $NssmExe set $name AppParameters $appParams
    & $NssmExe set $name AppDirectory $dir
    & $NssmExe set $name ObjectName "LocalSystem"
    & $NssmExe set $name AppStdout "C:\jcm\logs\$logName.out.log"
    & $NssmExe set $name AppStderr "C:\jcm\logs\$logName.err.log"
    & $NssmExe set $name AppRotateFiles 1
    & $NssmExe set $name AppRotateBytes 5242880
    & $NssmExe set $name AppExit Default Restart
    & $NssmExe set $name AppRestartDelay 5000
    & $NssmExe set $name Start SERVICE_AUTO_START
    Write-Host "Installed service $name"
}

New-Item -ItemType Directory -Force -Path "C:\jcm\logs" | Out-Null

# Disable destructive / conflicting tasks
foreach ($tn in @("Bilshenz-Watchdog", "JCM-Stack-Watchdog", "Bilshenz-DirectStart")) {
    schtasks /Change /TN $tn /DISABLE 2>$null
}

# MT5 API service
Install-NssmService "BilshenzMT5" "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    "-NoProfile -ExecutionPolicy Bypass -File C:\jcm\run-mt5.ps1" "C:\opt\bilshenz\mt5_trading_system\python" "mt5-api"

# Dashboard on port 8080 (8000 works externally; 3000 blocked at provider)
@'
Set-Location "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone"
$env:PORT = "8080"
$env:HOSTNAME = "0.0.0.0"
$staticSrc = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\static"
$staticDst = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone\.next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}
& "C:\Program Files\nodejs\node.exe" server.js
'@ | Set-Content C:\jcm\run-dashboard-8080.ps1 -Encoding UTF8

Install-NssmService "JCMDashboard" "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    "-NoProfile -ExecutionPolicy Bypass -File C:\jcm\run-dashboard-8080.ps1" `
    "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone" "dashboard"

# JCM sidecars
Install-NssmService "JCMSidecars" "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    "-NoProfile -ExecutionPolicy Bypass -File C:\jcm\run-sidecars.ps1" "C:\jcm" "sidecars"

# Keepalive (single-run script invoked every minute by scheduled task)
@'
$ErrorActionPreference = "Continue"
function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }
function Ensure([string]$name, [string]$script, [int]$port) {
    if (PortUp $port) { return }
    Add-Content "C:\jcm\logs\keepalive.log" "[$(Get-Date -Format o)] RESTART $name :$port"
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$script -WindowStyle Hidden
}
Ensure "MT5" "C:\jcm\run-mt5.ps1" 8765
Ensure "Dashboard" "C:\jcm\run-dashboard-8080.ps1" 8080
if (-not (PortUp 8083)) { Ensure "Sidecars" "C:\jcm\run-sidecars.ps1" 8083 }
if (-not (Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'run-forward-demo' })) {
    & "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
}
# Reset failsafe if MT5 healthy
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 5
    if ($m.connected) {
        $sf = "C:\logs\tradingbot\safety-state.json"
        if (Test-Path $sf) {
            $s = Get-Content $sf -Raw | ConvertFrom-Json
            if ($s.failsafe -or $s.consecutiveApiFailures -gt 0) {
                $s.failsafe = $false; $s.failsafeReason = $null; $s.consecutiveApiFailures = 0
                $s | ConvertTo-Json | Set-Content $sf -Encoding UTF8
            }
        }
    }
} catch {}
'@ | Set-Content C:\jcm\keepalive-once.ps1 -Encoding UTF8

# Firewall: 8080 for dashboard (3000 blocked at provider)
foreach ($rule in @(
    @{Name="JCM-Dashboard-8080"; Port=8080},
    @{Name="JCM-Dashboard-3000"; Port=3000},
    @{Name="JCM-API-8000"; Port=8000}
)) {
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $rule.Port | Out-Null
        Write-Host "Firewall: allow :$($rule.Port)"
    }
}

# Start services
foreach ($svc in @("BilshenzMT5", "JCMDashboard", "JCMSidecars")) {
    Start-Service $svc -ErrorAction SilentlyContinue
    if ((Get-Service $svc).Status -ne "Running") {
        & $NssmExe start $svc
    }
    Write-Host "Started $svc -> $((Get-Service $svc).Status)"
}

# Keepalive scheduled task (every 1 min, SYSTEM - only runs short script)
schtasks /Delete /TN "JCM-Keepalive-Min" /F 2>$null
schtasks /Create /TN "JCM-Keepalive-Min" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\jcm\keepalive-once.ps1" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F
Write-Host "Registered JCM-Keepalive-Min (every 1 min)"

# Ensure MT5 terminal running
$term = "C:\Program Files\MetaTrader 5 Exness\terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -EA SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"
    Write-Host "Started MT5 terminal"
    Start-Sleep 15
}

# Start forward bot + JCM API if down
if (-not (Get-NetTCPConnection -LocalPort 8000 -State Listen -EA SilentlyContinue)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\jcm\run-api.ps1" -WindowStyle Hidden
}
& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"

Start-Sleep -Seconds 20
& "C:\Users\Administrator\vps-live-test.ps1"

Write-Host "`nDashboard URL: http://104.194.140.203:8080" -ForegroundColor Green
Write-Host "API URL:       http://104.194.140.203:8000" -ForegroundColor Green
