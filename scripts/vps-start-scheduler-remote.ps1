$ErrorActionPreference = "Stop"
$roots = @(
    "C:\jcm-project",
    "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
)
$Root = $roots | Where-Object { Test-Path (Join-Path $_ "backend\.venv\Scripts\python.exe") } | Select-Object -First 1
if (-not $Root) { throw "No JCM backend venv found" }
Write-Host "Using root: $Root"

$Backend = Join-Path $Root "backend"
$LogDir = "C:\logs\jcm"
$Log = Join-Path $LogDir "agent-scheduler.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$py = Join-Path $Backend ".venv\Scripts\python.exe"

$existing = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if ($existing) {
    Write-Host "Already running PID $($existing.ProcessId)"
    exit 0
}

Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force -EA SilentlyContinue
$runner = "C:\Users\Administrator\jcm-agent-scheduler-runner.ps1"
@"
Set-Location '$Backend'
`$env:PYTHONUNBUFFERED='1'
& '$py' -m app.workers.agent_scheduler 2>&1 | Tee-Object -FilePath '$Log' -Append
"@ | Set-Content -Path $runner -Encoding UTF8

Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner
) | Out-Null
Start-Sleep -Seconds 6
$proc = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if ($proc) {
    Write-Host "OK scheduler PID $($proc.ProcessId)"
} else {
    Write-Host "FAIL - log tail:"
    if (Test-Path $Log) { Get-Content $Log -Tail 25 }
    exit 1
}
