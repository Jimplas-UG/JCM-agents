foreach ($log in @(
    "C:\logs\jcm\agent-scheduler.log",
    "C:\logs\jcm\scheduler-watchdog.log"
)) {
    Write-Host "=== $log ==="
    if (Test-Path $log) { Get-Content $log -Tail 20 } else { Write-Host "missing" }
}
