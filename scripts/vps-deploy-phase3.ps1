# Deploy institutional Phase 3 (safety + scale) to VPS.
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$files = @(
    "backend\app\services\ws_auth.py",
    "backend\app\services\agent_guard.py",
    "backend\app\services\agent_orchestrator.py",
    "backend\app\services\event_pipeline.py",
    "backend\app\api\routes\websocket.py",
    "backend\app\api\routes\mission_control_ui.py",
    "backend\app\api\routes\dashboard.py",
    "backend\app\api\routes\health.py",
    "backend\app\agents\infra_resilience\agent.py",
    "backend\app\agents\ceo_copilot\agent.py",
    "backend\app\config.py",
    "backend\app\static\mission-control.html"
)
foreach ($f in $files) {
    $src = Join-Path $Repo $f
    if (-not (Test-Path $src)) {
        Write-Error "Missing: $src"
    }
    $dest = "C:/jcm-project/$($f -replace '\\','/')"
    $dir = Split-Path $dest -Parent
    ssh jcm-vps "if not exist `"$($dir -replace '/','\')`" mkdir `"$($dir -replace '/','\')`"" 2>$null | Out-Null
    scp $src "jcm-vps:$dest"
}
ssh jcm-vps "C:\jcm\nssm\nssm.exe restart JCMAPI confirm"
Write-Host "Phase 3 deployed - platform should report institutional-v2" -ForegroundColor Green
