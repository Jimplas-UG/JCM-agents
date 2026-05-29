# Apply forward-bot stability fix and restart watchdog (one-time ops script)
$ErrorActionPreference = "Continue"

Write-Host "=== Applying forward-bot fix ===" -ForegroundColor Cyan

# Stop duplicate forward shells only (not MT5 API python)
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
} | ForEach-Object {
    Write-Host "Stopping forward PID $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

# End and restart Bilshenz watchdog so it loads patched deploy/watchdog.ts
schtasks /End /TN "Bilshenz-Watchdog" 2>$null
Start-Sleep -Seconds 3
schtasks /Run /TN "Bilshenz-Watchdog"
Write-Host "Restarted Bilshenz-Watchdog"

Start-Sleep -Seconds 5

# Start single detached forward worker
& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -AppDir "C:\opt\bilshenz"
Start-Sleep -Seconds 15

# Verify
$fwd = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
}
Write-Host "Forward processes: $($fwd.Count)"
if ($fwd) { $fwd | ForEach-Object { Write-Host "  PID $($_.ProcessId)" } }

Get-Content "C:\logs\tradingbot\forward-bot.log" -Tail 5 -ErrorAction SilentlyContinue
Write-Host "=== Fix applied ===" -ForegroundColor Green
