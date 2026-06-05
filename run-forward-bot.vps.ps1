param([string]$AppDir = 'C:\opt\bilshenz')
. (Join-Path $PSScriptRoot 'Import-TradingBotEnv.ps1')
$Backend = Join-Path $AppDir 'backend'
$LogDir = $env:TRADINGBOT_LOG_DIR
if (-not $LogDir) { $LogDir = 'C:\logs\tradingbot' }
$ErrLog = Join-Path $LogDir 'forward-bot.err.log'
$OutLog = Join-Path $LogDir 'forward-bot.out.log'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Test-ForwardAlive {
    $node = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
    }
    return [bool]$node
}

if (Test-ForwardAlive) {
    Write-Host 'Forward bot already active'
    exit 0
}

$task = Get-ScheduledTask -TaskName 'Bilshenz-ForwardBot' -ErrorAction SilentlyContinue
if ($task -and $task.State -eq 'Running') {
    Write-Host 'ForwardBot task already running'
    exit 0
}

Set-Location $Backend
$env:PRODUCTION_MODE = '1'
$env:PRODUCTION_NO_EXPIRY = '1'
$env:STRATEGY_FREEZE = '1'

$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = 'node.exe' }
$tsxCli = Join-Path $Backend 'node_modules\tsx\dist\cli.mjs'
if (-not (Test-Path $tsxCli)) {
    Write-Host 'FAIL: tsx missing'
    exit 1
}

# Append logs via cmd — avoids PowerShell pipe / redirect buffer stalls under SYSTEM
$logAppend = ">> `"$ErrLog`" 2>&1"
Start-Process -FilePath 'cmd.exe' `
    -ArgumentList @('/c', "node `"$tsxCli`" scripts/run-forward-demo-30d.ts $logAppend") `
    -WorkingDirectory $Backend `
    -WindowStyle Hidden
Write-Host 'Started forward bot'
exit 0
