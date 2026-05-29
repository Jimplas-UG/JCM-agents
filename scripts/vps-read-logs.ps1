$feErr = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\logs\frontend.err.log"
$apiErr = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\logs\api.err.log"
Write-Host "=== frontend.err.log ==="
if (Test-Path $feErr) { Get-Content $feErr } else { Write-Host "MISSING" }
Write-Host "`n=== api.err.log ==="
if (Test-Path $apiErr) { Get-Content $apiErr } else { Write-Host "MISSING" }
Write-Host "`n=== Try start dashboard sync test ==="
$standalone = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone"
$env:PORT = "3000"; $env:HOSTNAME = "0.0.0.0"
Set-Location $standalone
node server.js 2>&1 | Select-Object -First 15
