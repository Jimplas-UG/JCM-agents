Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -eq 'node.exe' } | ForEach-Object {
    Write-Host "PID $($_.ProcessId): $($_.CommandLine)"
}
Write-Host "--- watchdog.log tail ---"
if (Test-Path C:\logs\tradingbot\watchdog.log) { Get-Content C:\logs\tradingbot\watchdog.log -Tail 15 }
