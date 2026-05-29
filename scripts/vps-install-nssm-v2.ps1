# NSSM services v2 - direct node/python (no PowerShell wrapper)
$ErrorActionPreference = "Continue"
$NssmExe = "C:\jcm\nssm\nssm.exe"
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Standalone = Join-Path $Jcm "frontend\.next\standalone"
$PyDir = "C:\opt\bilshenz\mt5_trading_system\python"
$PyExe = Join-Path $PyDir ".venv\Scripts\python.exe"
$NodeExe = "C:\Program Files\nodejs\node.exe"

Write-Host "=== NSSM V2 INSTALL ===" -ForegroundColor Cyan

if (-not (Test-Path $NssmExe)) {
    Write-Host "Run vps-install-nssm-services.ps1 first to download NSSM"
    exit 1
}

# Copy static assets for dashboard
$staticSrc = Join-Path $Jcm "frontend\.next\static"
$staticDst = Join-Path $Standalone ".next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}

New-Item -ItemType Directory -Force -Path "C:\jcm\logs" | Out-Null

function Remove-Nssm([string]$name) {
    & $NssmExe stop $name confirm 2>$null
    Start-Sleep -Seconds 2
    & $NssmExe remove $name confirm 2>$null
    Start-Sleep -Seconds 1
}

function Install-Direct([string]$name, [string]$exe, [string]$params, [string]$dir, [hashtable]$envExtra, [string]$log) {
    Remove-Nssm $name
    & $NssmExe install $name $exe $params
    & $NssmExe set $name AppDirectory $dir
    if ($envExtra) {
        $envStr = ($envExtra.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
        & $NssmExe set $name AppEnvironmentExtra $envStr
    }
    & $NssmExe set $name AppStdout "C:\jcm\logs\$log.out.log"
    & $NssmExe set $name AppStderr "C:\jcm\logs\$log.err.log"
    & $NssmExe set $name AppRotateFiles 1
    & $NssmExe set $name AppExit Default Restart
    & $NssmExe set $name AppRestartDelay 5000
    & $NssmExe set $name Start SERVICE_AUTO_START
    & $NssmExe start $name
    Start-Sleep -Seconds 5
    $st = (Get-Service $name -EA SilentlyContinue).Status
    Write-Host "$name -> $st"
}

# MT5 terminal first (interactive session helps MT5 python connect)
$term = "C:\Program Files\MetaTrader 5 Exness\terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -EA SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"
    Write-Host "Started MT5 terminal"; Start-Sleep 20
}

Install-Direct "BilshenzMT5" $PyExe "main.py" $PyDir @{
    PORT = "8765"
    MT5_TERMINAL_PATH = "C:\Program Files\MetaTrader 5 Exness"
} "mt5-api"

Install-Direct "JCMDashboard" $NodeExe "server.js" $Standalone @{
    PORT = "8080"
    HOSTNAME = "0.0.0.0"
} "dashboard"

# Sidecars - forward only in NSSM, watchdog separate
$SidecarDir = Join-Path $Jcm "infra\bot-integration"
$SidecarPy = Join-Path $Jcm "backend\.venv\Scripts\python.exe"
Install-Direct "JCMSidecarFwd" $SidecarPy "stub_execution_layer.py forward" $SidecarDir @{} "sidecar-fwd"
Install-Direct "JCMSidecarWD" $SidecarPy "stub_execution_layer.py watchdog" $SidecarDir @{} "sidecar-wd"

# Remove old combined sidecar service if exists
Remove-Nssm "JCMSidecars"

# Firewall
foreach ($p in 8080,8000) {
    $n = "JCM-Port-$p"
    if (-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $n -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
    }
}

# Keepalive once script
@'
function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }
foreach ($svc in @("BilshenzMT5","JCMDashboard","JCMSidecarFwd","JCMSidecarWD")) {
    $s = Get-Service $svc -EA SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Start-Service $svc -EA SilentlyContinue; & "C:\jcm\nssm\nssm.exe" start $svc 2>$null }
}
if (-not (Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'run-forward-demo' })) {
    & "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
}
try {
    $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 5
    if ($m.connected -and (Test-Path "C:\logs\tradingbot\safety-state.json")) {
        $s = Get-Content "C:\logs\tradingbot\safety-state.json" -Raw | ConvertFrom-Json
        if ($s.failsafe -or $s.consecutiveApiFailures -gt 0) {
            $s.failsafe=$false; $s.failsafeReason=$null; $s.consecutiveApiFailures=0
            $s | ConvertTo-Json | Set-Content "C:\logs\tradingbot\safety-state.json" -Encoding UTF8
        }
    }
} catch {}
'@ | Set-Content C:\jcm\keepalive-once.ps1 -Encoding UTF8

# Keepalive task
schtasks /Create /TN "JCM-Keepalive-Min" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\jcm\keepalive-once.ps1" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F 2>$null

# Reset failsafe + forward bot
$sf = "C:\logs\tradingbot\safety-state.json"
if (Test-Path $sf) {
    $s = Get-Content $sf -Raw | ConvertFrom-Json
    $s.failsafe = $false; $s.failsafeReason = $null; $s.consecutiveApiFailures = 0
    $s | ConvertTo-Json | Set-Content $sf -Encoding UTF8
    Write-Host "Failsafe cleared"
}
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'run-forward-demo' } | ForEach-Object {
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
}
Start-Sleep -Seconds 2
& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"

# JCM API if not running
if (-not (Get-NetTCPConnection -LocalPort 8000 -State Listen -EA SilentlyContinue)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\jcm\run-api.ps1" -WindowStyle Hidden
    Start-Sleep -Seconds 8
}

Start-Sleep -Seconds 10
& "C:\Users\Administrator\vps-live-test.ps1"
Write-Host "`nDashboard: http://104.194.140.203:8080" -ForegroundColor Green
