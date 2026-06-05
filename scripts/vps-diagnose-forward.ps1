$log = "C:\logs\tradingbot\forward-bot.err.log"
if (Test-Path $log) {
    Write-Host "=== forward-bot.err.log tail ==="
    Get-Content $log -Tail 25
} else {
    Write-Host "No err log at $log"
}
$apiLog = "C:\logs\tradingbot\mt5-api.log"
if (Test-Path $apiLog) {
    Write-Host "=== mt5-api.log tail ==="
    Get-Content $apiLog -Tail 8
}
try {
    $r = Invoke-WebRequest "http://127.0.0.1:8765/openapi.json" -UseBasicParsing -TimeoutSec 8
    $j = $r.Content | ConvertFrom-Json
    $paths = $j.paths.PSObject.Properties.Name
    Write-Host "API paths: $($paths -join ', ')"
} catch {
    Write-Host "openapi: $($_.Exception.Message)"
}
