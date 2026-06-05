$all = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'forward-demo|bilshenz' }
Write-Host "matching_processes=$($all.Count)"
foreach ($p in $all) {
    $c = $p.CommandLine
    if ($c.Length -gt 200) { $c = $c.Substring(0,200) }
    Write-Host "$($p.Name) $($p.ProcessId) $c"
}
$err = Get-Item "C:\logs\tradingbot\forward-bot.err.log" -EA SilentlyContinue
if ($err) { Write-Host "err_log_mtime=$($err.LastWriteTime)" }
