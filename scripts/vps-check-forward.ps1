$f = "C:\logs\tradingbot\forward-bot.err.log"
if (Test-Path $f) {
    $i = Get-Item $f
    Write-Host "err.log size=$($i.Length) modified=$($i.LastWriteTime)"
    Get-Content $f -Tail 10
} else { Write-Host "no err.log" }
Write-Host "--- node processes ---"
Get-Process node -ErrorAction SilentlyContinue | ForEach-Object {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)"
    Write-Host "PID $($_.Id) $($p.CommandLine)"
}
