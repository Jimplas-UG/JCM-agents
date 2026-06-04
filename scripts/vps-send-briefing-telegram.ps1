# Executive briefing + Telegram — uses canonical Python job (same as 09:00 scheduler).
$ErrorActionPreference = "Stop"
$LogDir = "C:\logs\jcm"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "daily-briefing-telegram.log"

function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $msg"
    Add-Content -Path $LogFile -Value $line
    Write-Host $line
}

$Root = "C:\jcm-project"
if (-not (Test-Path "$Root\backend\.venv\Scripts\python.exe")) {
    $alt = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
    if (Test-Path "$alt\backend\.venv\Scripts\python.exe") { $Root = $alt }
}
$Backend = Join-Path $Root "backend"
$Py = Join-Path $Backend ".venv\Scripts\python.exe"
$EnvFile = Join-Path $Root ".env"

if (-not (Test-Path $Py)) { Write-Log "ERROR: venv not found"; exit 1 }
if (-not (Test-Path $EnvFile)) { Write-Log "ERROR: .env missing"; exit 1 }

Copy-Item $EnvFile (Join-Path $Backend ".env") -Force
Set-Location $Backend
Write-Log "daily_briefing_job --force"
& $Py -m app.workers.daily_briefing_job --force
$code = $LASTEXITCODE
if ($code -eq 0) { Write-Log "SUCCESS: briefing pipeline completed" }
else { Write-Log "ERROR: briefing pipeline exit $code" }
exit $code
