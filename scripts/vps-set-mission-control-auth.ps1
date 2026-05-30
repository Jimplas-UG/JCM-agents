# Set CEO Copilot HTTP Basic Auth credentials on VPS .env
# Usage:
#   $env:MISSION_CONTROL_USER = "your@email.com"
#   $env:MISSION_CONTROL_PASSWORD = "your-strong-password"
#   .\scripts\vps-set-mission-control-auth.ps1
$ErrorActionPreference = "Stop"
$envFile = "C:\jcm-project\.env"
if (-not (Test-Path $envFile)) { $envFile = "C:\jcm-project\backend\.env" }

$user = $env:MISSION_CONTROL_USER
$pass = $env:MISSION_CONTROL_PASSWORD
if (-not $user -or -not $pass) {
    Write-Error "Set MISSION_CONTROL_USER and MISSION_CONTROL_PASSWORD before running."
}

$map = @{
    MISSION_CONTROL_USER         = $user
    MISSION_CONTROL_PASSWORD     = $pass
    MISSION_CONTROL_REQUIRE_AUTH = "true"
}

$lines = Get-Content $envFile
$out = New-Object System.Collections.Generic.List[string]
$seen = @{}

foreach ($line in $lines) {
    if ($line -match '^\s*([^#=]+)=') {
        $k = $Matches[1].Trim()
        if ($map.ContainsKey($k)) {
            $out.Add("$k=$($map[$k])")
            $seen[$k] = $true
            continue
        }
    }
    $out.Add($line)
}

foreach ($k in $map.Keys) {
    if (-not $seen[$k]) { $out.Add("$k=$($map[$k])") }
}

$out | Set-Content $envFile -Encoding UTF8
Copy-Item $envFile "C:\jcm-project\backend\.env" -Force
Write-Host "Mission control auth configured in $envFile"

Get-ScheduledTask -TaskName "JCM-API-Sys" -ErrorAction SilentlyContinue | ForEach-Object {
    Stop-ScheduledTask -TaskName $_.TaskName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-ScheduledTask -TaskName $_.TaskName
    Write-Host "Restarted $($_.TaskName)"
}
