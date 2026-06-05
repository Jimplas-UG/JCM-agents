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

$existing = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d'
})
if ($existing.Count -eq 1) {
    Write-Host 'Forward bot already active PID' $existing[0].ProcessId
    exit 0
}
if ($existing.Count -gt 1) {
    foreach ($p in $existing) {
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

Set-Location $Backend
$env:PRODUCTION_MODE = '1'
$env:PRODUCTION_NO_EXPIRY = '1'
$env:STRATEGY_FREEZE = '1'
$env:RISK_PCT = '0.01'

$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = 'node.exe' }
$tsxCli = Join-Path $Backend 'node_modules\tsx\dist\cli.mjs'
if (-not (Test-Path $tsxCli)) {
    Write-Host 'FAIL: tsx missing'
    exit 1
}

# Detached node — cmd /c would exit and can strand short-lived workers under SYSTEM tasks
$args = "`"$tsxCli`" scripts/run-forward-demo-30d.ts"
Start-Process -FilePath $node `
    -ArgumentList $args `
    -WorkingDirectory $Backend `
    -WindowStyle Hidden `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog
Start-Sleep -Seconds 8
if (Test-ForwardAlive) {
    Write-Host 'Started forward bot'
    exit 0
}
Write-Host 'FAIL: forward bot did not stay up — check forward-bot.err.log'
exit 1
