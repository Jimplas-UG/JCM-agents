param([string]$AppDir = 'C:\opt\bilshenz')
$importEnv = Join-Path $PSScriptRoot 'Import-TradingBotEnv.ps1'
if (-not (Test-Path $importEnv)) {
    $importEnv = Join-Path (Join-Path $AppDir 'deploy\windows') 'Import-TradingBotEnv.ps1'
}
. $importEnv

$helper = Join-Path $PSScriptRoot 'vps-tsx-worker.ps1'
if (-not (Test-Path $helper)) { $helper = 'C:\jcm-project\scripts\vps-tsx-worker.ps1' }
if (Test-Path $helper) { . $helper }

$Backend = Join-Path $AppDir 'backend'
$Deploy = Join-Path $AppDir 'deploy'
$LogDir = $env:TRADINGBOT_LOG_DIR
if (-not $LogDir) { $LogDir = 'C:\logs\tradingbot' }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$marker = 'watchdog\.ts'
if (Test-TsxWorkerRunning $marker) {
    Stop-TsxWorkerDuplicates $marker | Out-Null
    $leaves = Get-TsxWorkerLeaves $marker
    Write-Host 'Watchdog already active PID' $leaves[0].ProcessId
    exit 0
}

Set-Location $Backend
$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = 'node.exe' }
$tsxCli = Join-Path $Backend 'node_modules\tsx\dist\cli.mjs'
if (-not (Test-Path $tsxCli)) {
    Write-Host 'FAIL: tsx missing'
    exit 1
}

$watchdogScript = Join-Path $Deploy 'watchdog.ts'
if (-not (Test-Path $watchdogScript)) {
    $watchdogScript = 'C:\jcm-project\watchdog.vps.ts'
}
if (-not (Test-Path $watchdogScript)) {
    Write-Host "FAIL: watchdog script missing"
    exit 1
}

$tsxArgs = @($tsxCli, $watchdogScript)
Start-Process -FilePath $node `
    -ArgumentList $tsxArgs `
    -WorkingDirectory $Backend `
    -WindowStyle Hidden
Start-Sleep -Seconds 10
if (Test-TsxWorkerRunning $marker) {
    Write-Host 'Started watchdog'
    exit 0
}
$pcount = Get-TsxWorkerNodeCount $marker
if ($pcount -ge 2) {
    Write-Host 'Started watchdog (tsx parent+child)'
    exit 0
}
$wdLog = Join-Path $LogDir 'watchdog.log'
if (Test-Path $wdLog) {
    $age = ((Get-Date) - (Get-Item $wdLog).LastWriteTime).TotalSeconds
    if ($age -lt 45) {
        Write-Host 'Started watchdog (log active)'
        exit 0
    }
}
Write-Host 'FAIL: watchdog did not stay up — check watchdog.log'
exit 1
