Write-Host "=== PROCESS CHECK $(Get-Date -Format o) ==="
foreach ($p in 8765,8791,8000,3000,8083,8084) {
    $l = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    Write-Host ":$p $(if ($l) { "UP PID $($l.OwningProcess)" } else { 'DOWN' })"
}
Write-Host "`nPython:"
Get-Process python -ErrorAction SilentlyContinue | ForEach-Object {
    $c = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
    Write-Host "  $($_.Id) $($c.Substring(0,[Math]::Min(100,$c.Length)))"
}
Write-Host "`nNode:"
Get-Process node -ErrorAction SilentlyContinue | ForEach-Object {
    $c = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
    Write-Host "  $($_.Id) $($c.Substring(0,[Math]::Min(120,$c.Length)))"
}
Write-Host "`nMT5 terminal: $(if (Get-Process terminal64 -EA SilentlyContinue) { 'RUNNING' } else { 'DOWN' })"
