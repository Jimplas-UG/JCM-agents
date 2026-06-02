$Backend = "C:\jcm-project\backend"
$Py = "$Backend\.venv\Scripts\python.exe"
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    ($_.Name -eq "python.exe" -and $_.CommandLine -match "app\.workers\.agent_scheduler") -or
    $_.CommandLine -match "jcm-scheduler-watchdog|jcm-scheduler-keepalive"
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 2
$args = "-m app.workers.agent_scheduler"
$cmd = "cd /d `"$Backend`" && start `"JCMScheduler`" /MIN `"$Py`" $args"
Start-Process cmd.exe -ArgumentList "/c", $cmd -WindowStyle Hidden
Start-Sleep 20
$p = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq "python.exe" -and $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if (-not $p) { throw "scheduler not running" }
Write-Host "scheduler PID $($p.ProcessId)"
