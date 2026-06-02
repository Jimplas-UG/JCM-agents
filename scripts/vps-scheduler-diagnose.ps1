$log = "C:\logs\jcm\agent-scheduler.log"
$py = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq "python.exe" -and $_.CommandLine -match "app\.workers\.agent_scheduler"
}
$wd = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "jcm-scheduler-watchdog"
}
Write-Host "python scheduler: $($py.Count)  watchdog: $($wd.Count)"
$py | ForEach-Object { Write-Host "  py $($_.ProcessId)" }
$wd | ForEach-Object { Write-Host "  wd $($_.ProcessId)" }
if (Test-Path $log) {
    Write-Host "`nLast 25 lines:"
    Get-Content $log -Tail 25
}
