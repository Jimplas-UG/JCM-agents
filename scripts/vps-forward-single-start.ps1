Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match 'run-forward-demo'
} | ForEach-Object {
    Write-Host "Stopping PID $($_.ProcessId)"
    Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
}
Start-Sleep 3
& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -AppDir "C:\opt\bilshenz"
Start-Sleep 5
$fwd = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
}
Write-Host "node_forward_count=$(@($fwd).Count)"
Start-Sleep 120
$fwd2 = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
}
Write-Host "after_120s=$(@($fwd2).Count)"
Get-Content "C:\logs\tradingbot\forward-bot.err.log" -Tail 5
