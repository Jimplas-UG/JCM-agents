# Start JCM 9-agent scheduler as a persistent background process (VPS).
$ErrorActionPreference = "Stop"
$Root = "C:\jcm-project"
$Backend = Join-Path $Root "backend"
$LogDir = "C:\logs\jcm"
$Log = Join-Path $LogDir "agent-scheduler.log"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$py = Join-Path $Backend ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) {
    Write-Host "FAIL: missing $py" -ForegroundColor Red
    exit 1
}

$existing = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if ($existing) {
    Write-Host "Agent scheduler already running PID $($existing.ProcessId)"
    exit 0
}

Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force -EA SilentlyContinue

$cmd = @"
Set-Location '$Backend'
`$env:PYTHONUNBUFFERED='1'
& '$py' -m app.workers.agent_scheduler 2>&1 | Tee-Object -FilePath '$Log' -Append
"@
$tmp = Join-Path $env:TEMP "jcm-agent-scheduler-runner.ps1"
Set-Content -Path $tmp -Value $cmd -Encoding UTF8

Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $tmp
) | Out-Null

Start-Sleep -Seconds 5
$proc = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "app\.workers\.agent_scheduler"
}
if ($proc) {
    Write-Host "OK agent_scheduler started PID $($proc.ProcessId)" -ForegroundColor Green
} else {
    Write-Host "WARN: scheduler not detected - check $Log" -ForegroundColor Yellow
    if (Test-Path $Log) { Get-Content $Log -Tail 20 }
    exit 1
}
