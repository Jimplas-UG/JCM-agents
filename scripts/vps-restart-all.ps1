# Smart stack restart — only start what's down (never kill running Bilshenz)
$ErrorActionPreference = "Continue"
$JcmRoot = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$LogFile = "C:\Users\Administrator\stack-restart.log"
function Log($m) { $l="[$(Get-Date -Format HH:mm:ss)] $m"; Write-Host $l; Add-Content $LogFile $l }

function Test-Port([int]$p) {
    return [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)
}

Log "=== SMART RESTART ==="

# Bilshenz via scheduled tasks (non-destructive)
$bTasks = @{
    8765 = "Bilshenz-MT5-API"
    8791 = "Bilshenz-DeskAPI"
}
foreach ($port in $bTasks.Keys) {
    if (-not (Test-Port $port)) {
        Log "Starting $($bTasks[$port]) (port $port down)"
        schtasks /Run /TN $bTasks[$port] 2>&1 | Out-Null
    } else {
        Log "Port $port OK"
    }
}
$fwd = Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match "run-forward-demo" }
if (-not $fwd) {
    Log "Starting Bilshenz-ForwardBot"
    schtasks /Run /TN "Bilshenz-ForwardBot" 2>&1 | Out-Null
}
schtasks /Run /TN "Bilshenz-Watchdog" 2>&1 | Out-Null

Start-Sleep -Seconds 20

# JCM platform
& "$JcmRoot\scripts\start-platform.ps1" 2>&1 | ForEach-Object { Log $_ }
Start-Sleep -Seconds 8

# JCM sidecars (Bilshenz deploy script — 8083/8084 health for infra agent)
$sidecars = "C:\opt\bilshenz\deploy\windows\start-jcm-sidecars.ps1"
if (Test-Path $sidecars) {
    & $sidecars 2>&1 | ForEach-Object { Log $_ }
} else {
    & "$JcmRoot\infra\bot-integration\start-execution-layer.vps.ps1" 2>&1 | ForEach-Object { Log $_ }
}
Start-Sleep -Seconds 5

# Dashboard :8080 for external access (infra port only — API stays :8000)
if (-not (Test-Port 8080)) {
    Log "Dashboard :8080 down — starting run-jcm-dashboard-8080.ps1"
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$JcmRoot\scripts\run-jcm-dashboard-8080.ps1" -WindowStyle Hidden
    Start-Sleep -Seconds 8
}
if (-not (Test-Port 3000)) {
    Log "Dashboard :3000 down — optional local fallback"
    & "C:\Users\Administrator\vps-start-dashboard.ps1" 2>&1 | ForEach-Object { Log $_ }
    Start-Sleep -Seconds 5
}

foreach ($port in 8765,8791,8000,8080,8083,8084) {
    Log ":$port $(if (Test-Port $port) { 'UP' } else { 'DOWN' })"
}
Log "=== DONE ==="
