$ErrorActionPreference = "Continue"
Write-Host "Force-start execution stack"

$conn = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue | Select-Object -First 1
if ($conn) {
    $pid8765 = $conn.OwningProcess
    Write-Host "Port 8765 PID $pid8765"
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pid8765" -EA SilentlyContinue
    if ($proc) { Write-Host "  $($proc.CommandLine)" }
}

schtasks /End /TN Bilshenz-MT5-API-Sys 2>$null
Start-Sleep 5
Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue | ForEach-Object {
    Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue
}
Start-Sleep 3
schtasks /Run /TN Bilshenz-MT5-API-Sys 2>$null
Start-Sleep 25

try {
    $r = Invoke-WebRequest "http://127.0.0.1:8765/openapi.json" -UseBasicParsing -TimeoutSec 8
    Write-Host "openapi OK len=$($r.Content.Length)"
} catch {
    Write-Host "openapi fail: $($_.Exception.Message)"
}
try {
    $rc = Invoke-RestMethod "http://127.0.0.1:8765/api/reconnect" -Method POST -TimeoutSec 10
    Write-Host "reconnect ok=$($rc.ok)"
} catch {
    Write-Host "reconnect fail: $($_.Exception.Message)"
}

$Backend = "C:\opt\bilshenz\backend"
$vj = "$Backend\scripts\validation"
$vt = "$Backend\validation"
if (-not (Test-Path $vj)) { cmd /c mklink /J "$vj" "$vt" 2>$null }
$fwdLauncher = "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
if (Test-Path $fwdLauncher) {
    (Get-Content $fwdLauncher -Raw) -replace 'run-forward-demo-30d\.ts','scripts/run-forward-demo-30d.ts' | Set-Content $fwdLauncher -Encoding UTF8
}
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 2
& $fwdLauncher -AppDir "C:\opt\bilshenz"
Start-Sleep 20
$fwd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match "run-forward-demo" })
Write-Host "forward_count=$($fwd.Count)"
if (Test-Path "C:\logs\tradingbot\forward-bot.err.log") {
    Get-Content "C:\logs\tradingbot\forward-bot.err.log" -Tail 5
}
