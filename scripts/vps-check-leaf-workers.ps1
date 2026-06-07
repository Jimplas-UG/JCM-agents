. "C:\jcm-project\scripts\vps-tsx-worker.ps1" -ErrorAction SilentlyContinue
if (-not (Get-Command Test-TsxWorkerRunning -EA SilentlyContinue)) {
    function Test-TsxWorkerRunning($p) {
        @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
            $_.CommandLine -match "loader\.mjs.*$p"
        }).Count -ge 1
    }
    function Get-TsxWorkerNodeCount($p) {
        @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
            $_.CommandLine -match $p
        }).Count
    }
}

$fLeaf = Test-TsxWorkerRunning 'run-forward-demo-30d'
$wLeaf = Test-TsxWorkerRunning 'watchdog\.ts'
$fPids = Get-TsxWorkerNodeCount 'run-forward-demo-30d'
$wPids = Get-TsxWorkerNodeCount 'watchdog\.ts'
Write-Host "Forward: leaf=$fLeaf nodePIDs=$fPids"
Write-Host "Watchdog: leaf=$wLeaf nodePIDs=$wPids"
Get-Content C:\logs\tradingbot\forward-bot.err.log -Tail 2 -EA SilentlyContinue
Get-Content C:\logs\tradingbot\watchdog.log -Tail 3 -EA SilentlyContinue
Get-Content C:\logs\jcm\daily-briefing-telegram.log -Tail 4 -EA SilentlyContinue
