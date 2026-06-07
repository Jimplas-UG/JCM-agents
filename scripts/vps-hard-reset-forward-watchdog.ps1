# Hard reset forward + watchdog with verification
$ErrorActionPreference = "Continue"

function Stop-All-TradingWorkers {
    Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and ($_.CommandLine -match 'run-forward-demo-30d|watchdog\.ts|watchdog\.vps\.ts')
    } | ForEach-Object {
        Write-Host "Stop PID $($_.ProcessId)"
        Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue
    }
    Start-Sleep 5
}

function Get-ForwardLeaf {
    @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d' -and $_.CommandLine -notmatch 'tsx\\dist\\cli\.mjs'
    })
}

function Get-WatchdogLeaf {
    @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match 'watchdog\.ts' -and $_.CommandLine -notmatch 'tsx\\dist\\cli\.mjs'
    })
}

Stop-All-TradingWorkers
Copy-Item "C:\jcm-project\watchdog.vps.ts" "C:\opt\bilshenz\deploy\watchdog.ts" -Force
Copy-Item "C:\jcm-project\run-forward-bot.vps.ps1" "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -Force
Copy-Item "C:\jcm-project\run-watchdog.vps.ps1" "C:\opt\bilshenz\deploy\windows\run-watchdog.ps1" -Force

& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -AppDir "C:\opt\bilshenz"
Start-Sleep 12
$fwd = Get-ForwardLeaf
Write-Host "Forward leaf count after start: $($fwd.Count)"
if ($fwd.Count -eq 0) {
    Write-Host "FAIL forward did not start"
    Get-Content C:\logs\tradingbot\forward-bot.err.log -Tail 8 -EA SilentlyContinue
    exit 1
}

& "C:\opt\bilshenz\deploy\windows\run-watchdog.ps1" -AppDir "C:\opt\bilshenz"
Start-Sleep 10
$wd = Get-WatchdogLeaf
Write-Host "Watchdog leaf count: $($wd.Count)"

Start-Sleep 70
$fwd2 = Get-ForwardLeaf
$wd2 = Get-WatchdogLeaf
Write-Host "After 70s - Forward: $($fwd2.Count) Watchdog: $($wd2.Count)"
Get-Content C:\logs\tradingbot\watchdog.log -Tail 6 -EA SilentlyContinue

if ($fwd2.Count -ne 1 -or $wd2.Count -ne 1) { exit 1 }
Write-Host "OK both workers stable"
exit 0
