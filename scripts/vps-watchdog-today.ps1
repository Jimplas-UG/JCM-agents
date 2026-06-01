$log = "C:\logs\tradingbot\watchdog.log"
if (-not (Test-Path $log)) { Write-Host "log missing: $log"; exit 1 }
$today = (Get-Date).ToString("yyyy-MM-dd")
$lines = Get-Content $log -Tail 300 -EA SilentlyContinue | Where-Object { $_ -match $today }
Write-Host "watchdog.log entries on ${today}: $($lines.Count) (last 300 lines scanned)"
if ($lines.Count -eq 0) {
    Write-Host "Last 8 lines (any date):"
    Get-Content $log -Tail 8 -EA SilentlyContinue | ForEach-Object { Write-Host $_ }
} else {
    $lines | Select-Object -Last 15 | ForEach-Object { Write-Host $_ }
}
