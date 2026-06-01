# Deploy CEO executive briefing + Telegram alert + restart API and agent scheduler.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Jcm = "C:/Users/Administrator/Documents/JCM agents/JCM-agents"

$paths = @(
    "backend/app/services/executive_briefing",
    "backend/app/services/alerting.py",
    "backend/app/agents/ceo_copilot/agent.py",
    "backend/app/workers/agent_scheduler.py",
    "backend/app/api/routes/dashboard.py",
    "backend/app/config.py",
    "backend/app/config.vps.py"
)

Write-Host "=== Deploy executive briefing ===" -ForegroundColor Cyan
$mkdirScript = Join-Path $Root "scripts\vps-mkdir-eb.ps1"
scp $mkdirScript "jcm-vps:C:/Users/Administrator/vps-mkdir-eb.ps1"
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-mkdir-eb.ps1"
foreach ($rel in $paths) {
    $local = Join-Path $Root $rel
    if (-not (Test-Path $local)) { throw "Missing $local" }
    $remote = "$Jcm/$($rel -replace '\\','/')"
    if (Test-Path $local -PathType Container) {
        Get-ChildItem $local -Recurse -File | ForEach-Object {
            $sub = $_.FullName.Substring($local.Length).TrimStart('\').Replace('\', '/')
            $dest = "$Jcm/$($rel -replace '\\','/')/$sub"
            Write-Host "  scp $($_.Name) -> $dest"
            scp $_.FullName "jcm-vps:$dest"
        }
    } else {
        Write-Host "  scp $rel"
        scp $local "jcm-vps:$remote"
    }
}

$remotePs1 = @'
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
New-Item -ItemType Directory -Force -Path "$Jcm\backend\app\services\executive_briefing" | Out-Null
$eb = Join-Path $Jcm "backend\app\services\executive_briefing\service.py"
if (-not (Test-Path $eb)) { throw "Executive briefing not deployed: $eb" }
Copy-Item "$Jcm\.env" "$Jcm\backend\.env" -Force -EA SilentlyContinue
schtasks /End /TN JCM-API-Sys 2>$null | Out-Null
Start-Sleep -Seconds 3
schtasks /Run /TN JCM-API-Sys 2>$null | Out-Null
Start-Sleep -Seconds 12
$h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 15
Write-Host "API health: $($h.status)"
$sched = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match "app\.workers\.agent_scheduler" }
if ($sched) {
    Stop-Process -Id $sched.ProcessId -Force -EA SilentlyContinue
    Start-Sleep -Seconds 2
}
& "$Jcm\scripts\vps-start-agent-scheduler.ps1"
Write-Host "Scheduler restarted"
'@

$tmpRemote = Join-Path $env:TEMP "vps-deploy-eb-remote.ps1"
Set-Content -Path $tmpRemote -Value $remotePs1 -Encoding UTF8
scp $tmpRemote "jcm-vps:C:/Users/Administrator/deploy-eb-remote.ps1"
ssh jcm-vps "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\deploy-eb-remote.ps1"

Write-Host "Briefing: http://104.194.140.203:8000/mission-control (Executive tab)" -ForegroundColor Green
Write-Host "Ensure VPS .env has TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID for 09:00 alert." -ForegroundColor Yellow
