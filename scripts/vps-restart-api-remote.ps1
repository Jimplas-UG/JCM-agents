# Restart JCM API on VPS (prefers JCMAPI NSSM service when installed).
$ErrorActionPreference = "Stop"
$Nssm = "C:\jcm\nssm\nssm.exe"
if ((Get-Service "JCMAPI" -EA SilentlyContinue) -and (Test-Path $Nssm)) {
    & $Nssm restart JCMAPI confirm | Out-Null
    Start-Sleep -Seconds 18
} else {
    & "$PSScriptRoot\vps-mission-control-up.ps1"
    exit $LASTEXITCODE
}

$h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 15
if ($h.status -ne "healthy") { throw "API unhealthy" }
Write-Host "Health: $($h.status)"
