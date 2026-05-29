# JCM stack watchdog — restart if critical ports are down (run via Task Scheduler every 5 min)
$ErrorActionPreference = "Continue"
$ports = @(8765, 8791, 8000, 3000, 8083, 8084)
$down = @()
foreach ($p in $ports) {
    if (-not (Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue)) {
        $down += $p
    }
}
if ($down.Count -eq 0) { exit 0 }

$log = "C:\Users\Administrator\watchdog-restart.log"
Add-Content $log "[$(Get-Date -Format o)] Ports down: $($down -join ',') — restarting"
if ($down -contains 3000) {
    & "C:\Users\Administrator\vps-start-dashboard.ps1" *>> $log
}
if ($down | Where-Object { $_ -in 8083,8084 }) {
    & "C:\Users\Administrator\start-sidecars.ps1" *>> $log
}
if ($down | Where-Object { $_ -in 8765,8791,8000 }) {
    & "C:\Users\Administrator\vps-restart-all.ps1" *>> $log
}
