# Start JCM 9-agent scheduler as a persistent background process (VPS).
$ErrorActionPreference = "Stop"
$roots = @("C:\jcm-project", "C:\Users\Administrator\Documents\JCM agents\JCM-agents")
$Root = $roots | Where-Object { Test-Path (Join-Path $_ "backend\.venv\Scripts\python.exe") } | Select-Object -First 1
if (-not $Root) { throw "No JCM backend venv found under jcm-project or JCM-agents" }
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

$runner = "C:\Users\Administrator\jcm-scheduler-keepalive.ps1"
@"
Set-Location '$Backend'
`$env:PYTHONUNBUFFERED='1'
while (`$true) {
    & '$py' -m app.workers.agent_scheduler >> '$Log' 2>&1
    Start-Sleep -Seconds 10
}
"@ | Set-Content -Path $runner -Encoding UTF8

Start-Process powershell -WindowStyle Hidden -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $runner
) | Out-Null

Start-Sleep -Seconds 6
$proc = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "agent_scheduler|jcm-scheduler-keepalive"
}
$tn = "JCM-Agent-Scheduler"
schtasks /Create /TN $tn /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$runner`"" /SC ONSTART /RU Administrator /RL HIGHEST /F 2>$null | Out-Null

if ($proc) {
    Write-Host "OK agent_scheduler PID $($proc.ProcessId) · daily briefing 09:00 Africa/Kampala"
} else {
    Write-Host "WARN: scheduler not detected - check $Log"
    if (Test-Path $Log) { Get-Content $Log -Tail 20 }
    exit 1
}
