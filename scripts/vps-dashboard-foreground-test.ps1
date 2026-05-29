$standalone = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone"
$env:PORT = "3000"
$env:HOSTNAME = "0.0.0.0"
Write-Host "Testing dashboard server.js (10s)..."
$job = Start-Job { Set-Location "C:\Users\Administrator\Documents\JCM agents\JCM-agents\frontend\.next\standalone"; $env:PORT="3000"; $env:HOSTNAME="0.0.0.0"; node server.js 2>&1 }
Start-Sleep -Seconds 10
Receive-Job $job
$p = Get-NetTCPConnection -LocalPort 3000 -State Listen -EA SilentlyContinue
Write-Host "Port 3000: $(if($p){'UP'}else{'DOWN'})"
Stop-Job $job -EA SilentlyContinue; Remove-Job $job -EA SilentlyContinue
