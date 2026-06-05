# Deploy allocator readiness package to VPS.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$VpsHost = if ($env:VPS_HOST) { $env:VPS_HOST } else { "jcm-vps" }
$B = "C:/opt/bilshenz/backend"
$J = "C:/jcm-project"

$files = @(
    @{ L = "$Root\infra\bilshenz\validation\allocatorGates.ts"; R = "$B/validation/allocatorGates.ts" },
    @{ L = "$Root\infra\bilshenz\run-allocator-readiness.ts"; R = "$B/scripts/run-allocator-readiness.ts" },
    @{ L = "$Root\backend\app\services\allocator_readiness.py"; R = "$J/backend/app/services/allocator_readiness.py" },
    @{ L = "$Root\backend\app\services\allocator_tear_sheet.py"; R = "$J/backend/app/services/allocator_tear_sheet.py" },
    @{ L = "$Root\backend\app\services\execution_halt.py"; R = "$J/backend/app/services/execution_halt.py" },
    @{ L = "$Root\backend\app\scripts\run_allocator_pipeline.py"; R = "$J/backend/app/scripts/run_allocator_pipeline.py" },
    @{ L = "$Root\backend\app\scripts\close_stale_jcm_opens.py"; R = "$J/backend/app/scripts/close_stale_jcm_opens.py" },
    @{ L = "$Root\backend\app\agents\portfolio_risk\agent.py"; R = "$J/backend/app/agents/portfolio_risk/agent.py" },
    @{ L = "$Root\backend\app\api\routes\dashboard.py"; R = "$J/backend/app/api/routes/dashboard.py" },
    @{ L = "$Root\scripts\vps-run-allocator-pipeline.ps1"; R = "$J/scripts/vps-run-allocator-pipeline.ps1" },
    @{ L = "$Root\scripts\vps-ensure-forward-bot.ps1"; R = "$J/scripts/vps-ensure-forward-bot.ps1" }
)
foreach ($f in $files) { scp $f.L "${VpsHost}:$($f.R)" }

ssh $VpsHost "powershell -NoProfile -ExecutionPolicy Bypass -File C:/jcm-project/scripts/vps-run-allocator-pipeline.ps1"
