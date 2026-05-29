# JCM observability stack: dashboard :8080 + sidecars :8083/:8084 (blocking SYSTEM task)
$ErrorActionPreference = "Continue"
$Log = "C:\jcm\logs\observability.log"
New-Item -ItemType Directory -Force -Path "C:\jcm\logs" | Out-Null

function Log($m) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m"
    Add-Content -Path $Log -Value $line -Encoding UTF8
}

function PortUp([int]$port) {
    [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
}

function Ensure([string]$name, [int]$port, [string]$script) {
    if (PortUp $port) { return }
    Log "START $name :$port"
    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script -WindowStyle Hidden
    Start-Sleep -Seconds 8
    if (PortUp $port) { Log "OK $name :$port" } else { Log "FAIL $name :$port" }
}

Log "=== Observability stack started ==="

while ($true) {
    Ensure "Dashboard" 8080 "C:\jcm\run-dashboard-8080.ps1"
    if (-not (PortUp 8083)) { Ensure "Sidecars" 8083 "C:\jcm\run-sidecars-all.ps1" }
    elseif (-not (PortUp 8084)) { Ensure "Sidecars" 8084 "C:\jcm\run-sidecars-all.ps1" }
    Start-Sleep -Seconds 60
}
