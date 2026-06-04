# Scheduled task: keep agent_scheduler alive (survives reboot; Administrator account).
$ErrorActionPreference = "Stop"
$wd = "C:\Users\Administrator\jcm-scheduler-watchdog.ps1"
if (-not (Test-Path $wd)) { throw "Missing $wd" }

$tn = "JCM-Scheduler-Watchdog"
schtasks /End /TN $tn 2>$null | Out-Null
schtasks /Delete /TN $tn /F 2>$null | Out-Null

$tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$wd`""
# Administrator so .env paths match briefing tasks
$null = schtasks /Create /TN $tn /TR $tr /SC ONSTART /RU Administrator /RL HIGHEST /F 2>&1
if ($LASTEXITCODE -ne 0) {
    schtasks /Create /TN $tn /TR $tr /SC ONSTART /RL HIGHEST /F | Out-Null
}
schtasks /Run /TN $tn | Out-Null

Start-Sleep -Seconds 50
$py = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq "python.exe" -and $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if (-not $py) { throw "agent_scheduler not running" }
Write-Host "OK scheduler watchdog running"
