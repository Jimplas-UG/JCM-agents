$ErrorActionPreference = "Stop"
$Backend = "C:\opt\bilshenz\backend"
if (-not (Test-Path $Backend)) {
    throw "Backend path not found: $Backend"
}

Set-Location $Backend
Write-Host "Running 12-month MT5 backtest from $Backend"
npm run backtest:xau12mo:mt5
