# VPS: keep a single agent_scheduler process alive (09:00 executive briefing).
$ErrorActionPreference = "Continue"
$Backend = "C:\jcm-project\backend"
$Py = "$Backend\.venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
    $Backend = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend"
    $Py = "$Backend\.venv\Scripts\python.exe"
}
Copy-Item "C:\jcm-project\.env" (Join-Path $Backend ".env") -Force -EA SilentlyContinue

function Get-SchedulerProcs {
    @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.Name -eq "python.exe" -and $_.CommandLine -match "app\.workers\.agent_scheduler"
    })
}

function Start-Scheduler {
    Start-Process -FilePath $Py -ArgumentList @(
        "-m", "app.workers.agent_scheduler"
    ) -WorkingDirectory $Backend -WindowStyle Hidden
}

while ($true) {
    $procs = Get-SchedulerProcs
    if ($procs.Count -gt 1) {
        $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
        Start-Sleep -Seconds 5
    } elseif ($procs.Count -eq 0) {
        Start-Scheduler
        Start-Sleep -Seconds 25
    }
    Start-Sleep -Seconds 30
}
