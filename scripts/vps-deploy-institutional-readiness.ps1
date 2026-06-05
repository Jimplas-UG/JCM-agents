# Deploy institutional readiness upgrade (no BSv3.2 strategy changes).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$HostName = if ($env:VPS_HOST) { $env:VPS_HOST } else { "jcm-vps" }
$Bilshenz = "C:/opt/bilshenz"
$Jcm = "C:/jcm-project"

$files = @(
    @{ Local = "$Root\infra\bilshenz\validation\institutionalMetrics.ts"; Remote = "$Bilshenz/backend/validation/institutionalMetrics.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\tradeReconciliation.ts"; Remote = "$Bilshenz/backend/validation/tradeReconciliation.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\stressChecks.ts"; Remote = "$Bilshenz/backend/validation/stressChecks.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\institutionalReadiness.ts"; Remote = "$Bilshenz/backend/validation/institutionalReadiness.ts" },
    @{ Local = "$Root\infra\bilshenz\run-institutional-readiness.ts"; Remote = "$Bilshenz/backend/scripts/run-institutional-readiness.ts" },
    @{ Local = "$Root\infra\bilshenz\run-forward-demo-30d.ts"; Remote = "$Bilshenz/backend/scripts/run-forward-demo-30d.ts" },
    @{ Local = "$Root\infra\bilshenz\production\safetyControls.ts"; Remote = "$Bilshenz/backend/production/safetyControls.ts" },
    @{ Local = "$Root\backend\app\services\institutional_readiness.py"; Remote = "$Jcm/backend/app/services/institutional_readiness.py" },
    @{ Local = "$Root\backend\app\api\routes\dashboard.py"; Remote = "$Jcm/backend/app/api/routes/dashboard.py" },
    @{ Local = "$Root\backend\app\scripts\reconcile_trades.py"; Remote = "$Jcm/backend/app/scripts/reconcile_trades.py" },
    @{ Local = "$Root\scripts\vps-run-institutional-readiness.ps1"; Remote = "$Jcm/scripts/vps-run-institutional-readiness.ps1" },
    @{ Local = "$Root\scripts\vps-ensure-forward-bot.ps1"; Remote = "$Jcm/scripts/vps-ensure-forward-bot.ps1" },
    @{ Local = "$Root\scripts\vps-audit-forward-alignment.ps1"; Remote = "C:/Users/Administrator/vps-audit-forward-alignment.ps1" }
)

Write-Host "=== Deploy institutional readiness ===" -ForegroundColor Cyan
foreach ($f in $files) {
    scp $f.Local "${HostName}:$($f.Remote)"
}

$remote = @'
$pkg = "C:\opt\bilshenz\backend\package.json"
if (Test-Path $pkg) {
  $j = Get-Content $pkg -Raw | ConvertFrom-Json
  if (-not $j.scripts.'institutional:readiness') {
    $j.scripts | Add-Member -NotePropertyName 'institutional:readiness' -NotePropertyValue 'tsx scripts/run-institutional-readiness.ts' -Force
    $j | ConvertTo-Json -Depth 10 | Set-Content $pkg -Encoding UTF8
  }
}
Copy-Item "C:\jcm-project\run-forward-bot.vps.ps1" "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -Force -EA SilentlyContinue
C:\jcm\nssm\nssm.exe restart JCMAPI confirm
Start-Sleep 12
& "C:\jcm-project\scripts\vps-run-institutional-readiness.ps1"
'@
$tmp = Join-Path $env:TEMP "deploy-inst-readiness-remote.ps1"
Set-Content $tmp $remote -Encoding UTF8
scp $tmp "${HostName}:C:/Users/Administrator/deploy-inst-readiness-remote.ps1"
ssh $HostName "powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\deploy-inst-readiness-remote.ps1"

Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "API: http://104.194.140.203:8000/dashboard/institutional-readiness"
