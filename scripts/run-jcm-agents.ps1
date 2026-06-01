# Delegates to vps-start-agent-scheduler (persistent hidden worker).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$starter = Join-Path $here "vps-start-agent-scheduler.ps1"
if (Test-Path $starter) {
    & $starter
    exit $LASTEXITCODE
}
$Root = Split-Path -Parent $here
$Backend = Join-Path $Root "backend"
Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force -EA SilentlyContinue
$py = Join-Path $Backend ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python.exe" }
Set-Location $Backend
& $py -m app.workers.agent_scheduler
