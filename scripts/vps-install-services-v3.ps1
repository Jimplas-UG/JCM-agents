# Windows services v3: junction paths, NSSM wrappers, keepalive, forward bot reset
# Run on VPS as Administrator: powershell -File C:\Users\Administrator\vps-install-services-v3.ps1
$ErrorActionPreference = "Continue"

$NssmExe = "C:\jcm\nssm\nssm.exe"
$JcmReal = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Jcm = "C:\jcm-project"
$Bilshenz = "C:\opt\bilshenz"

Write-Host "=== JCM SERVICES V3 ===" -ForegroundColor Cyan

# --- NSSM binary ---
if (-not (Test-Path $NssmExe)) {
    New-Item -ItemType Directory -Force -Path "C:\jcm\nssm" | Out-Null
    $zip = "$env:TEMP\nssm.zip"
    Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
    Copy-Item "$env:TEMP\nssm-2.24\win64\nssm.exe" $NssmExe -Force
}

# --- Junction (no spaces for NSSM AppDirectory) ---
if (-not (Test-Path $Jcm)) {
    cmd /c "mklink /J `"$Jcm`" `"$JcmReal`""
    Write-Host "Junction: $Jcm -> $JcmReal"
}

New-Item -ItemType Directory -Force -Path "C:\jcm\logs" | Out-Null

# --- Short-path launchers in C:\jcm ---
$Standalone = Join-Path $Jcm "frontend\.next\standalone"
$staticSrc = Join-Path $Jcm "frontend\.next\static"
$staticDst = Join-Path $Standalone ".next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}

@'
Set-Location "C:\jcm-project\frontend\.next\standalone"
$env:PORT = "8080"
$env:HOSTNAME = "0.0.0.0"
$staticSrc = "C:\jcm-project\frontend\.next\static"
$staticDst = "C:\jcm-project\frontend\.next\standalone\.next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}
& "C:\Program Files\nodejs\node.exe" server.js
'@ | Set-Content C:\jcm\run-dashboard-8080.ps1 -Encoding UTF8

@'
Set-Location "C:\jcm-project\backend"
Copy-Item "C:\jcm-project\.env" .env -Force -EA SilentlyContinue
& "C:\jcm-project\backend\.venv\Scripts\python.exe" -m uvicorn app.main:app --host 0.0.0.0 --port 8000
'@ | Set-Content C:\jcm\run-api.ps1 -Encoding UTF8

@'
. "C:\opt\bilshenz\deploy\windows\Import-TradingBotEnv.ps1"
$mt5Path = "C:\Program Files\MetaTrader 5 Exness"
$term = Join-Path $mt5Path "terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -ErrorAction SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"
    Start-Sleep -Seconds 30
}
Set-Location "C:\opt\bilshenz\mt5_trading_system\python"
$env:PORT = "8765"
$env:MT5_TERMINAL_PATH = $mt5Path
& "C:\opt\bilshenz\mt5_trading_system\python\.venv\Scripts\python.exe" main.py
'@ | Set-Content C:\jcm\run-mt5.ps1 -Encoding UTF8

@'
Set-Location "C:\jcm-project\infra\bot-integration"
& "C:\jcm-project\backend\.venv\Scripts\python.exe" stub_execution_layer.py forward
'@ | Set-Content C:\jcm\run-sidecar-fwd.ps1 -Encoding UTF8

@'
Set-Location "C:\jcm-project\infra\bot-integration"
& "C:\jcm-project\backend\.venv\Scripts\python.exe" stub_execution_layer.py watchdog
'@ | Set-Content C:\jcm\run-sidecar-wd.ps1 -Encoding UTF8

@'
Set-Location "C:\opt\bilshenz\backend"
$env:PRODUCTION_MODE = "1"
$env:PRODUCTION_NO_EXPIRY = "1"
$env:STRATEGY_FREEZE = "1"
$LogDir = "C:\logs\tradingbot"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$ErrLog = Join-Path $LogDir "forward-bot.err.log"
$tsxCli = "C:\opt\bilshenz\backend\node_modules\tsx\dist\cli.mjs"
$cmd = "node `"$tsxCli`" scripts/run-forward-demo-30d.ts 2>&1 | ForEach-Object { `$_ | Out-File -FilePath `"$ErrLog`" -Append -Encoding utf8; `$_ }"
powershell.exe -NoProfile -WindowStyle Hidden -Command $cmd
'@ | Set-Content C:\jcm\run-forward-bot.ps1 -Encoding UTF8

# --- NSSM helpers ---
function Remove-Nssm([string]$name) {
    if (-not (Get-Service $name -EA SilentlyContinue)) { return }
    & $NssmExe stop $name confirm 2>$null
    Start-Sleep -Seconds 2
    & $NssmExe remove $name confirm 2>$null
    Start-Sleep -Seconds 1
}

function Install-PsService([string]$name, [string]$script, [string]$log) {
    Remove-Nssm $name
    $ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $NssmExe install $name $ps
    & $NssmExe set $name AppParameters "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
    & $NssmExe set $name AppDirectory "C:\jcm"
    & $NssmExe set $name ObjectName "LocalSystem"
    & $NssmExe set $name AppStdout "C:\jcm\logs\$log.out.log"
    & $NssmExe set $name AppStderr "C:\jcm\logs\$log.err.log"
    & $NssmExe set $name AppRotateFiles 1
    & $NssmExe set $name AppRotateBytes 5242880
    & $NssmExe set $name AppRestartDelay 5000
    & $NssmExe set $name Start SERVICE_AUTO_START
    & $NssmExe start $name
    Start-Sleep -Seconds 4
    $st = (Get-Service $name -EA SilentlyContinue).Status
    Write-Host "$name -> $st"
}

function Kill-Port([int]$port) {
    Get-NetTCPConnection -LocalPort $port -State Listen -EA SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue
    }
}

# --- Disable conflicting tasks ---
foreach ($t in @(
    "Bilshenz-Watchdog", "JCM-Stack-Watchdog", "Bilshenz-DirectStart",
    "JCM-Dashboard-Adm", "JCM-Dashboard-Sys", "JCM-Sidecars-Adm", "JCM-Sidecars-Sys"
)) {
    schtasks /Change /TN $t /DISABLE 2>$null
}

# --- MT5 terminal ---
$term = "C:\Program Files\MetaTrader 5 Exness\terminal64.exe"
if ((Test-Path $term) -and -not (Get-Process terminal64 -EA SilentlyContinue)) {
    Start-Process $term -ArgumentList "/algotrading"
    Write-Host "Started MT5 terminal"
    Start-Sleep -Seconds 25
}

# --- Keepalive loop (NSSM long-runner; sidecars/forward bot die if only Start-Process) ---
@'
$ErrorActionPreference = "Continue"
$Log = "C:\jcm\logs\keepalive.log"
function Log($m) { "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $m" | Add-Content $Log }
function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }
function EnsurePort($name, $port, $script) {
    if (PortUp $port) { return }
    Log "RESTART $name :$port down"
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$script -WindowStyle Hidden
}
function EnsureService($svc) {
    $s = Get-Service $svc -EA SilentlyContinue
    if ($s -and $s.Status -ne "Running") {
        Log "START service $svc"
        Start-Service $svc -EA SilentlyContinue
        & "C:\jcm\nssm\nssm.exe" start $svc 2>$null
    }
}
while ($true) {
    foreach ($svc in @("BilshenzMT5","JCMDashboard","JCMAPI")) { EnsureService $svc }
    EnsurePort "MT5" 8765 "C:\jcm\run-mt5.ps1"
    EnsurePort "Dashboard" 8080 "C:\jcm\run-dashboard-8080.ps1"
    EnsurePort "API" 8000 "C:\jcm\run-api.ps1"
    EnsurePort "SidecarFwd" 8083 "C:\jcm\run-sidecar-fwd.ps1"
    EnsurePort "SidecarWD" 8084 "C:\jcm\run-sidecar-wd.ps1"
    if (-not (Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'run-forward-demo' })) {
        Log "START forward bot"
        Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\jcm\run-forward-bot.ps1" -WindowStyle Hidden
    }
    try {
        $m = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 5
        if ($m.connected -and (Test-Path "C:\logs\tradingbot\safety-state.json")) {
            $s = Get-Content "C:\logs\tradingbot\safety-state.json" -Raw | ConvertFrom-Json
            if ($s.failsafe -or ($s.consecutiveApiFailures -gt 0)) {
                $s.failsafe = $false; $s.failsafeReason = $null; $s.consecutiveApiFailures = 0
                $s | ConvertTo-Json | Set-Content "C:\logs\tradingbot\safety-state.json" -Encoding UTF8
                Log "Failsafe cleared"
            }
        }
    } catch {}
    Start-Sleep -Seconds 60
}
'@ | Set-Content C:\jcm\keepalive-loop.ps1 -Encoding UTF8

# --- Install services (PowerShell wrappers avoid path/arg issues) ---
Kill-Port 8765
Install-PsService "BilshenzMT5" "C:\jcm\run-mt5.ps1" "mt5-api"
Install-PsService "JCMDashboard" "C:\jcm\run-dashboard-8080.ps1" "dashboard"

if (-not (Get-NetTCPConnection -LocalPort 8000 -State Listen -EA SilentlyContinue)) {
    Kill-Port 8000
    Install-PsService "JCMAPI" "C:\jcm\run-api.ps1" "jcm-api"
} else {
    Write-Host "JCMAPI -> skipped (port 8000 already up)"
}

foreach ($legacy in @("JCMSidecarFwd", "JCMSidecarWD", "JCMSidecars")) { Remove-Nssm $legacy }
Install-PsService "JCMKeepalive" "C:\jcm\keepalive-loop.ps1" "keepalive"

# --- Firewall ---
foreach ($p in 8080, 8000, 8765) {
    $n = "JCM-Port-$p"
    if (-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $n -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
    }
}

# One-shot keepalive for manual runs (scheduled task backup)
Copy-Item C:\jcm\keepalive-loop.ps1 C:\jcm\keepalive-once.ps1 -Force -EA SilentlyContinue
@'
$ErrorActionPreference = "Continue"
$Log = "C:\jcm\logs\keepalive.log"
function Log($m) { "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) $m" | Add-Content $Log }
function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }
function EnsurePort($name, $port, $script) {
    if (PortUp $port) { return }
    Log "RESTART $name :$port down"
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$script -WindowStyle Hidden
}
foreach ($svc in @("BilshenzMT5","JCMDashboard","JCMAPI","JCMKeepalive")) {
    $s = Get-Service $svc -EA SilentlyContinue
    if ($s -and $s.Status -ne "Running") { Log "START service $svc"; Start-Service $svc -EA SilentlyContinue }
}
EnsurePort "MT5" 8765 "C:\jcm\run-mt5.ps1"
EnsurePort "Dashboard" 8080 "C:\jcm\run-dashboard-8080.ps1"
EnsurePort "API" 8000 "C:\jcm\run-api.ps1"
EnsurePort "SidecarFwd" 8083 "C:\jcm\run-sidecar-fwd.ps1"
EnsurePort "SidecarWD" 8084 "C:\jcm\run-sidecar-wd.ps1"
if (-not (Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'run-forward-demo' })) {
    Log "START forward bot"
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\jcm\run-forward-bot.ps1" -WindowStyle Hidden
}
'@ | Set-Content C:\jcm\keepalive-once.ps1 -Encoding UTF8

schtasks /Create /TN "JCM-Keepalive-Min" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\jcm\keepalive-once.ps1" /SC MINUTE /MO 1 /RU SYSTEM /RL HIGHEST /F 2>$null

# --- Clear failsafe + restart forward bot ---
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
Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","C:\jcm\run-forward-bot.ps1" -WindowStyle Hidden

Start-Sleep -Seconds 15
if (Test-Path "C:\Users\Administrator\vps-live-test.ps1") {
    & "C:\Users\Administrator\vps-live-test.ps1"
}
Write-Host "`nDashboard: http://104.194.140.203:8080" -ForegroundColor Green
Write-Host "API:       http://104.194.140.203:8000/health" -ForegroundColor Green
