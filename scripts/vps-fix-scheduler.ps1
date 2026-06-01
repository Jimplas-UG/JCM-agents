# Keep agent scheduler alive via scheduled task (runs at logon + on demand).
$ErrorActionPreference = "Stop"
$Root = "C:\jcm-project"
if (-not (Test-Path "$Root\backend\.venv\Scripts\python.exe")) {
    $Root = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
}
$Backend = Join-Path $Root "backend"
$Py = Join-Path $Backend ".venv\Scripts\python.exe"
$Log = "C:\logs\jcm\agent-scheduler.log"
New-Item -ItemType Directory -Force -Path "C:\logs\jcm" | Out-Null
Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force -EA SilentlyContinue

Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "agent_scheduler"
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Seconds 2

$runner = "C:\Users\Administrator\jcm-scheduler-keepalive.ps1"
@"
Set-Location '$Backend'
`$env:PYTHONUNBUFFERED='1'
while (`$true) {
    try {
        & '$Py' -m app.workers.agent_scheduler 2>&1 | Tee-Object -FilePath '$Log' -Append
    } catch {
        "`$(Get-Date -Format o) scheduler exited: `$_" | Add-Content '$Log'
    }
    Start-Sleep -Seconds 10
}
"@ | Set-Content -Path $runner -Encoding UTF8

Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner
) | Out-Null
Start-Sleep -Seconds 8
$p = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match "agent_scheduler|jcm-scheduler-keepalive" }
Write-Host "Processes: $($p.Count)"
$p | ForEach-Object { Write-Host "  $($_.ProcessId)" }
if (Test-Path $Log) { Get-Content $Log -Tail 5 }
