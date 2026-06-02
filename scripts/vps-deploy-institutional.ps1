# Deploy institutional optimization to VPS (API + scheduler restart).
$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$files = @(
    "backend\app\services\agent_registry.py",
    "backend\app\services\agent_orchestrator.py",
    "backend\app\services\mission_memory.py",
    "backend\app\services\live_dashboard.py",
    "backend\app\agents\ceo_copilot\agent.py",
    "backend\app\workers\agent_scheduler.py",
    "backend\app\api\routes\health.py",
    "backend\app\api\routes\dashboard.py",
    "backend\app\static\mission-control.html",
    "backend\app\services\executive_briefing\context.py",
    "backend\app\services\executive_briefing\service.py",
    "backend\app\services\event_pipeline.py",
    "backend\app\agents\quant_memory\agent.py",
    "backend\app\agents\research_evolution\agent.py",
    "backend\app\agents\infra_resilience\agent.py",
    "backend\app\db\redis_client.py",
    "backend\app\metrics\prometheus.py"
)
foreach ($f in $files) {
    $src = Join-Path $Repo $f
    $dest = "C:/jcm-project/$($f -replace '\\','/')"
    $dir = Split-Path $dest -Parent
    ssh jcm-vps "if not exist `"$($dir -replace '/','\')`" mkdir `"$($dir -replace '/','\')`"" 2>$null | Out-Null
    scp $src "jcm-vps:$dest"
}
ssh jcm-vps "C:\jcm\nssm\nssm.exe restart JCMAPI confirm"
Write-Host "Deployed institutional upgrade - refresh Mission Control" -ForegroundColor Green
