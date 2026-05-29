# Fix: use $argLine not $args (reserved in PowerShell)
$ErrorActionPreference = "Stop"
$JcmReal = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Jcm = "C:\jcm-project"
if (-not (Test-Path $Jcm)) {
    cmd /c "mklink /J `"$Jcm`" `"$JcmReal`""
}
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

function Register-Task([string]$name, [string]$argLine, [string]$desc) {
    $full = "-NoProfile -ExecutionPolicy Bypass $argLine"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $full
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $desc -Force | Out-Null
    schtasks /End /TN $name 2>$null
    Start-Sleep -Seconds 2
    schtasks /Run /TN $name 2>&1 | Out-Null
    Write-Host "OK $name -> $full"
}

function Register-PythonTask([string]$name, [string]$script, [string]$pyArgs, [string]$dir, [string]$desc) {
    $py = Join-Path $Jcm "backend\.venv\Scripts\python.exe"
    $action = New-ScheduledTaskAction -Execute $py -Argument "$script $pyArgs" -WorkingDirectory $dir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description $desc -Force | Out-Null
    schtasks /End /TN $name 2>$null
    Start-Sleep -Seconds 2
    schtasks /Run /TN $name 2>&1 | Out-Null
    Write-Host "OK $name -> python $script $pyArgs"
}

function Write-Utf8NoBom([string]$path, [string]$content) {
    [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding $false))
}

if (-not (Test-Path "C:\jcm")) { New-Item -ItemType Directory -Force -Path "C:\jcm" | Out-Null }
Write-Utf8NoBom "C:\jcm\run-dashboard-8080.ps1" @'
$ErrorActionPreference = "Continue"
$log = "C:\jcm\logs\dashboard.log"
try {
    Set-Location "C:\jcm-project\frontend\.next\standalone"
    $env:PORT = "8080"
    $env:HOSTNAME = "0.0.0.0"
    $staticSrc = "C:\jcm-project\frontend\.next\static"
    $staticDst = "C:\jcm-project\frontend\.next\standalone\.next\static"
    if (Test-Path $staticSrc) {
        New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
        Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
    }
    & "C:\Program Files\nodejs\node.exe" server.js *>> $log 2>&1
} catch {
    $_ | Out-File $log -Append -Encoding utf8
}
'@

Write-Utf8NoBom "C:\jcm\run-sidecar-fwd.ps1" @'
Set-Location "C:\jcm-project\infra\bot-integration"
& "C:\jcm-project\backend\.venv\Scripts\python.exe" stub_execution_layer.py forward
'@

Write-Utf8NoBom "C:\jcm\run-sidecar-wd.ps1" @'
Set-Location "C:\jcm-project\infra\bot-integration"
& "C:\jcm-project\backend\.venv\Scripts\python.exe" stub_execution_layer.py watchdog
'@

Write-Utf8NoBom "C:\jcm\run-sidecars-all.ps1" @'
Set-Location "C:\jcm-project\infra\bot-integration"
& "C:\jcm-project\backend\.venv\Scripts\python.exe" stub_execution_layer.py all
'@

Copy-Item "$Jcm\scripts\run-jcm-observability-stack.ps1" "C:\jcm\run-jcm-observability-stack.ps1" -Force -EA SilentlyContinue
if (-not (Test-Path "C:\jcm\run-jcm-observability-stack.ps1")) {
    Write-Utf8NoBom "C:\jcm\run-jcm-observability-stack.ps1" (Get-Content "$Jcm\scripts\run-jcm-observability-stack.ps1" -Raw -EA SilentlyContinue)
}

Register-Task "Bilshenz-MT5-API-Sys" '-File "C:\opt\bilshenz\deploy\windows\run-mt5-api.ps1" -AppDir "C:\opt\bilshenz"' "MT5 :8765"
Start-Sleep -Seconds 25
Register-Task "Bilshenz-DeskAPI-Sys" '-File "C:\opt\bilshenz\deploy\windows\run-desk-api.ps1" -AppDir "C:\opt\bilshenz"' "Desk :8791"
Start-Sleep -Seconds 15
Register-Task "Bilshenz-ForwardBot-Sys" '-File "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -AppDir "C:\opt\bilshenz"' "Forward bot"
Start-Sleep -Seconds 10
Register-Task "JCM-API-Sys" "-File `"$Jcm\scripts\run-jcm-api.ps1`"" "JCM API :8000"
Start-Sleep -Seconds 10
Register-Task "JCM-Agents-Sys" "-File `"$Jcm\scripts\run-jcm-agents.ps1`"" "9 agent scheduler"
Start-Sleep -Seconds 5

# Single blocking task for dashboard + sidecars (replaces separate tasks that failed as SYSTEM)
foreach ($legacy in @("JCM-Dashboard-Sys", "JCM-SidecarFwd-Sys", "JCM-SidecarWD-Sys", "JCM-Sidecars-Sys")) {
    if (Get-ScheduledTask -TaskName $legacy -EA SilentlyContinue) {
        schtasks /End /TN $legacy 2>$null | Out-Null
        Unregister-ScheduledTask -TaskName $legacy -Confirm:$false -EA SilentlyContinue | Out-Null
    }
}
Register-Task "JCM-Observability-Sys" "-File C:\jcm\run-jcm-observability-stack.ps1" "Dashboard :8080 + sidecars :8083/:8084"
Register-Task "Bilshenz-Watchdog-Sys" '-File "C:\opt\bilshenz\deploy\windows\run-watchdog.ps1" -AppDir "C:\opt\bilshenz"' "Bilshenz watchdog"

foreach ($p in 8080, 8000, 8765, 8791, 8083, 8084) {
    $n = "JCM-Port-$p"
    if (-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $n -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
    }
}
Write-Host "Done - waiting 30s..."
Start-Sleep -Seconds 30
& "C:\Users\Administrator\vps-live-test.ps1"
