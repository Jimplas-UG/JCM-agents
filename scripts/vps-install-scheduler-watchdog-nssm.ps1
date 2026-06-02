# NSSM service: watchdog keeps agent_scheduler alive (09:00 CEO briefing).
$ErrorActionPreference = "Stop"
$NssmExe = "C:\jcm\nssm\nssm.exe"
if (-not (Test-Path $NssmExe)) { throw "NSSM missing (run vps-install-api-nssm.ps1 first)" }

$wd = "C:\Users\Administrator\jcm-scheduler-watchdog.ps1"
if (-not (Test-Path $wd)) { throw "Missing $wd" }

Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "jcm-scheduler-watchdog|jcm-scheduler-keepalive"
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq "python.exe" -and $_.CommandLine -match "app\.workers\.agent_scheduler"
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }

$svc = "JCMSchedulerWatchdog"
$existing = Get-Service $svc -EA SilentlyContinue
if ($existing) {
    if ($existing.Status -eq "Running") { & $NssmExe stop $svc confirm 2>$null; Start-Sleep 3 }
    & $NssmExe remove $svc confirm 2>$null
    Start-Sleep 2
}
$old = Get-Service "JCMScheduler" -EA SilentlyContinue
if ($old) {
    & $NssmExe stop JCMScheduler confirm 2>$null
    & $NssmExe remove JCMScheduler confirm 2>$null
}

$ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
& $NssmExe install $svc $ps "-NoProfile -ExecutionPolicy Bypass -File `"$wd`""
& $NssmExe set $svc AppStdout "C:\logs\jcm\scheduler-watchdog.log"
& $NssmExe set $svc AppStderr "C:\logs\jcm\scheduler-watchdog.log"
& $NssmExe set $svc AppExit Default Restart
& $NssmExe set $svc AppRestartDelay 5000
& $NssmExe set $svc Start SERVICE_AUTO_START
& $NssmExe start $svc

Start-Sleep -Seconds 45
$wdProc = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "jcm-scheduler-watchdog"
}
$py = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq "python.exe" -and $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if (-not $wdProc) { throw "watchdog service not running" }
if (-not $py) { throw "agent_scheduler not running" }
Write-Host "OK watchdog + scheduler running"
