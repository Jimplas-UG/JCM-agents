# Monitor forward process survival (run on VPS)
$App = "C:\opt\bilshenz"
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and ($_.CommandLine -match 'run-forward-demo-30d|watchdog\.ts')
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 3
& "$App\deploy\windows\run-forward-bot.ps1" -AppDir $App
$waits = @(5, 10, 15, 30, 30, 30)
$t = 0
foreach ($w in $waits) {
    Start-Sleep -Seconds $w
    $t += $w
    $all = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo'
    })
    Write-Host "=== t+${t}s count=$($all.Count) ==="
    foreach ($p in $all) {
        $cl = $p.CommandLine
        if ($cl.Length -gt 140) { $cl = $cl.Substring(0, 140) + "..." }
        Write-Host "PID $($p.ProcessId): $cl"
    }
    $log = Get-Content C:\logs\tradingbot\forward-bot.err.log -Tail 1 -EA SilentlyContinue
    Write-Host "log: $log"
}
