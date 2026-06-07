& "C:\Users\Administrator\vps-start-forward-watchdog.ps1"
foreach ($i in 1..6) {
    Start-Sleep -Seconds 30
    $f = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.CommandLine -match 'run-forward-demo-30d'
    }).Count
    $w = @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.CommandLine -match 'watchdog\.ts'
    }).Count
    $fl = Get-Content C:\logs\tradingbot\forward-bot.err.log -Tail 1 -EA SilentlyContinue
    $wl = Get-Content C:\logs\tradingbot\watchdog.log -Tail 1 -EA SilentlyContinue
    Write-Host "[$i] fwd=$f wd=$w"
    Write-Host "  $fl"
    Write-Host "  $wl"
}
