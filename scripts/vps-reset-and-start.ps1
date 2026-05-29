# Reset failsafe + start all + verify
$ErrorActionPreference = "Continue"
$safety = "C:\logs\tradingbot\safety-state.json"
if (Test-Path $safety) {
    $s = Get-Content $safety -Raw | ConvertFrom-Json
    $s.failsafe = $false
    $s.failsafeReason = $null
    $s.consecutiveApiFailures = 0
    $s | ConvertTo-Json | Set-Content $safety -Encoding UTF8
    Write-Host "Failsafe CLEARED"
}
& "C:\Users\Administrator\vps-start-all.ps1"
