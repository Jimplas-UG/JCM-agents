Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('node.exe','tsx.exe') } | ForEach-Object {
    Write-Host "PID $($_.ProcessId) $($_.CommandLine)"
}
