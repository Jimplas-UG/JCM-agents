$ErrorActionPreference = "Stop"
$Backend = "C:\opt\bilshenz\backend"
if (-not (Test-Path $Backend)) {
    throw "Backend path not found: $Backend"
}

Set-Location $Backend
Write-Host "Running 12-month realistic live-profile backtest from $Backend"
npm run backtest:xau12mo:realistic
