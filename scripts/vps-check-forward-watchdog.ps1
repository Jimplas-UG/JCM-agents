$fwd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'run-forward-demo-30d' -and $_.CommandLine -notmatch 'tsx\\dist\\cli\.mjs'
})
$wd = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'watchdog\.ts|watchdog\.vps\.ts' -and $_.CommandLine -notmatch 'tsx\\dist\\cli\.mjs'
})
Write-Host "Forward workers: $($fwd.Count)"
if ($fwd.Count -gt 0) { Write-Host "  PID $($fwd[0].ProcessId)" }
Write-Host "Watchdog workers: $($wd.Count)"
if ($wd.Count -gt 0) { Write-Host "  PID $($wd[0].ProcessId)" }
foreach ($log in @('forward-bot.err.log', 'watchdog.log')) {
    $p = "C:\logs\tradingbot\$log"
    if (Test-Path $p) {
        Write-Host "--- tail $log ---"
        Get-Content $p -Tail 4
    }
}
