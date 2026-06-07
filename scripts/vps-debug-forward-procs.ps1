Write-Host "=== All node matching forward ==="
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo'
} | ForEach-Object {
    $isCli = $_.CommandLine -match 'tsx\\dist\\cli\.mjs'
    Write-Host "PID $($_.ProcessId) cli=$isCli"
    Write-Host $_.CommandLine
    Write-Host "---"
}
