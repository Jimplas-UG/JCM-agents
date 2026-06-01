# Deploy forward validation audit fixes to Bilshenz VPS (observability only).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Bilshenz = "C:/opt/bilshenz/backend"

$files = @(
    @{ Local = "$Root\infra\bilshenz\validation\types.ts"; Remote = "$Bilshenz/validation/types.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\alerts.ts"; Remote = "$Bilshenz/validation/alerts.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\driftAnalysis.ts"; Remote = "$Bilshenz/validation/driftAnalysis.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\forwardDemoStore.ts"; Remote = "$Bilshenz/validation/forwardDemoStore.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\logForwardEvent.ts"; Remote = "$Bilshenz/validation/logForwardEvent.ts" },
    @{ Local = "$Root\infra\bilshenz\validation\executionAuditReport.ts"; Remote = "$Bilshenz/validation/executionAuditReport.ts" },
    @{ Local = "$Root\infra\bilshenz\run-forward-execution-audit.ts"; Remote = "$Bilshenz/scripts/run-forward-execution-audit.ts" }
)

foreach ($f in $files) {
    Write-Host "scp $($f.Local)"
    scp $f.Local "jcm-vps:$($f.Remote)"
}

Write-Host "Re-running audit on VPS..."
ssh jcm-vps "cd C:\opt\bilshenz\backend && npm run audit:forward-execution"
