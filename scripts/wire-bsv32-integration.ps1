# Wire JCM platform to BSv3.2 (Bilshenz) and start both stacks.
param(
    [string]$Bsv32Home = ""
)

$ErrorActionPreference = "Continue"
. "$PSScriptRoot\jcm-env.ps1"
$JcmRoot = Get-JcmRoot -FromScript $PSScriptRoot
$Bilshenz = Get-Bsv32Home -Root $JcmRoot -Override $Bsv32Home

Write-Host "=== Wire BSv3.2 + JCM ===" -ForegroundColor Cyan
Write-Host "BSV32_HOME: $Bilshenz" -ForegroundColor Gray

# Sync JCM env to backend/frontend
Copy-Item (Join-Path $JcmRoot ".env") (Join-Path $JcmRoot "backend\.env") -Force
$feEnv = Join-Path $JcmRoot "frontend\.env.local"
if (Test-Path $feEnv) {
    Copy-Item (Join-Path $JcmRoot ".env") $feEnv -Force
}

# BSv3.2 execution layer
$startScript = Join-Path $Bilshenz "deploy\windows\start-all-now.ps1"
if (Test-Path $startScript) {
    & $startScript -AppDir $Bilshenz
} else {
    Write-Host "WARN: BSv3.2 not found at $Bilshenz" -ForegroundColor Yellow
    Write-Host "      Set path: .\scripts\set-bsv32-home.ps1 -Path `"D:\your\BSv3.2`"" -ForegroundColor Yellow
}

# JCM platform (API, workers, dashboard, sidecars)
& (Join-Path $JcmRoot "scripts\start-platform.ps1")

Start-Sleep -Seconds 3

Write-Host "`n=== Integration checks ===" -ForegroundColor Cyan
$checks = @(
    @{ Name = "MT5 API"; Url = "http://127.0.0.1:8765/health" },
    @{ Name = "Desk API"; Url = "http://127.0.0.1:8791/health" },
    @{ Name = "JCM API"; Url = "http://127.0.0.1:8000/health" },
    @{ Name = "Forward sidecar"; Url = "http://127.0.0.1:8083/health" },
    @{ Name = "Watchdog sidecar"; Url = "http://127.0.0.1:8084/health" }
)
foreach ($c in $checks) {
    try {
        $r = Invoke-WebRequest -Uri $c.Url -UseBasicParsing -TimeoutSec 8
        Write-Host "  $($c.Name): OK ($($r.StatusCode))"
    } catch {
        Write-Host "  $($c.Name): FAIL" -ForegroundColor Red
    }
}

$publicUrl = Get-EnvFileValue -Root $JcmRoot -Name "PLATFORM_PUBLIC_URL" -Default "http://127.0.0.1:8000"
$dashboardUrl = $publicUrl -replace ':8000', ':3000'
Write-Host "`nDashboard: $dashboardUrl" -ForegroundColor Green
Write-Host "JCM API:   $publicUrl" -ForegroundColor Green
Write-Host "BSv3.2:    $Bilshenz (MT5 :8765, desk :8791)" -ForegroundColor Green
