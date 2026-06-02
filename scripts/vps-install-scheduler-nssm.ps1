# Install JCM agent scheduler as NSSM service (09:00 CEO briefing).
$ErrorActionPreference = "Stop"
$NssmExe = "C:\jcm\nssm\nssm.exe"
if (-not (Test-Path $NssmExe)) { throw "NSSM missing (run vps-install-api-nssm.ps1 first)" }
$Backend = "C:\jcm-project\backend"
$Py = "$Backend\.venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
    $Backend = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend"
    $Py = "$Backend\.venv\Scripts\python.exe"
}

New-Item -ItemType Directory -Force -Path C:\jcm, C:\logs\jcm | Out-Null
Copy-Item "C:\jcm-project\.env" (Join-Path $Backend ".env") -Force -EA SilentlyContinue

Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "agent_scheduler|jcm-scheduler-keepalive"
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }

$runner = @"
Set-Location '$Backend'
`$env:PYTHONUNBUFFERED = '1'
& '$Py' -m app.workers.agent_scheduler
"@
Set-Content -Path C:\jcm\run-agent-scheduler.ps1 -Value $runner -Encoding UTF8

$svc = "JCMScheduler"
$existing = Get-Service $svc -EA SilentlyContinue
if ($existing) {
    if ($existing.Status -eq "Running") { & $NssmExe stop $svc confirm 2>$null; Start-Sleep 3 }
    & $NssmExe remove $svc confirm 2>$null
    Start-Sleep 2
}

$ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
& $NssmExe install $svc $ps "-NoProfile -ExecutionPolicy Bypass -File C:\jcm\run-agent-scheduler.ps1"
& $NssmExe set $svc AppDirectory $Backend
& $NssmExe set $svc AppStdout "C:\logs\jcm\agent-scheduler.log"
& $NssmExe set $svc AppStderr "C:\logs\jcm\agent-scheduler.log"
& $NssmExe set $svc AppExit Default Restart
& $NssmExe set $svc AppRestartDelay 5000
& $NssmExe set $svc Start SERVICE_AUTO_START
& $NssmExe start $svc

Start-Sleep -Seconds 20
$p = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if (-not $p) { throw "JCMScheduler not running" }
Write-Host "JCMScheduler running - briefing 09:00 Africa/Kampala"
