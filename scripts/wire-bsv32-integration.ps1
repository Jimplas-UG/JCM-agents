# Wire JCM platform to Bilshenz (C:\opt\bilshenz) and start both stacks.
$ErrorActionPreference = "Continue"
$JcmRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Bilshenz = "C:\opt\bilshenz"

Write-Host "=== Wire BSv3.2 + JCM ===" -ForegroundColor Cyan

# Sync JCM env to backend/frontend
Copy-Item (Join-Path $JcmRoot ".env") (Join-Path $JcmRoot "backend\.env") -Force
Copy-Item (Join-Path $JcmRoot ".env") (Join-Path $JcmRoot "frontend\.env.local") -Force

# Bilshenz execution layer
if (Test-Path (Join-Path $Bilshenz "deploy\windows\start-all-now.ps1")) {
    & (Join-Path $Bilshenz "deploy\windows\start-all-now.ps1") -AppDir $Bilshenz
} else {
    Write-Host "WARN: Bilshenz not found at $Bilshenz" -ForegroundColor Yellow
}

# JCM platform (API, workers, dashboard, sidecars)
& (Join-Path $JcmRoot "scripts\start-platform.ps1")

Start-Sleep -Seconds 3

Write-Host "`n=== Integration checks ===" -ForegroundColor Cyan
$checks = @(
    @{ Name = "MT5 API"; Url = "http://127.0.0.1:8765/health" },
    @{ Name = "Desk API"; Url = "http://127.0.0.1:8791/health" },
    @{ Name = "JCM API"; Url = "http://127.0.0.1:8000/health" },
    @{ Name = "Forward sidecar"; Url = "http://127.0.0.1:8083/health"; Headers = @{ Authorization = "Bearer jcm_s930px6rvhanj7kt5qi8fy41ocdu" } },
    @{ Name = "Watchdog sidecar"; Url = "http://127.0.0.1:8084/health"; Headers = @{ Authorization = "Bearer jcm_caxs285n7flj0t4muord1z63hgbi" } }
)
foreach ($c in $checks) {
    try {
        $params = @{ Uri = $c.Url; UseBasicParsing = $true; TimeoutSec = 8 }
        if ($c.Headers) { $params.Headers = $c.Headers }
        $r = Invoke-WebRequest @params
        Write-Host "  $($c.Name): OK ($($r.StatusCode))"
    } catch {
        Write-Host "  $($c.Name): FAIL" -ForegroundColor Red
    }
}

$secret = "26nvWoyYBrR4GMuNZeaFLJP1OXc75Idi"
$env:EVENT_WEBHOOK_SECRET = $secret
$env:API_URL = "http://127.0.0.1:8000"
$py = Join-Path $JcmRoot "backend\.venv\Scripts\python.exe"
if (Test-Path $py) {
    & $py (Join-Path $JcmRoot "scripts\sample_event_ingest.py")
}

Write-Host "`nDashboard: http://104.194.140.203:3000" -ForegroundColor Green
Write-Host "JCM API:   http://104.194.140.203:8000" -ForegroundColor Green
Write-Host "Bilshenz:  C:\opt\bilshenz (MT5 :8765, desk :8791)" -ForegroundColor Green
