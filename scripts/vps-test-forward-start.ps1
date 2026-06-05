$launcher = "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
Write-Host "Launcher line:"
Select-String -Path $launcher -Pattern "run-forward-demo"
& $launcher -AppDir "C:\opt\bilshenz"
Start-Sleep 25
$fwd = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "run-forward-demo"
}
Write-Host "process_count=$($fwd.Count)"
foreach ($p in $fwd) {
    $cmd = $p.CommandLine
    if ($cmd.Length -gt 160) { $cmd = $cmd.Substring(0, 160) }
    Write-Host "PID $($p.ProcessId): $cmd"
}
if (Test-Path "C:\logs\tradingbot\forward-bot.err.log") {
    Write-Host "--- err tail ---"
    Get-Content "C:\logs\tradingbot\forward-bot.err.log" -Tail 6
}
