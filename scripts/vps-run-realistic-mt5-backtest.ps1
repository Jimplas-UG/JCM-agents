# Realistic BSv3.2 backtest - live MT5 feed + equity, fresh run (no forward-demo data).
$ErrorActionPreference = "Stop"
$Backend = "C:\opt\bilshenz\backend"
$LogDir = "C:\logs\tradingbot"
$ReportDir = Join-Path $Backend "validation\data"
New-Item -ItemType Directory -Force -Path $LogDir, $ReportDir | Out-Null

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = Join-Path $LogDir "backtest-realistic-mt5-$stamp.log"

Write-Host "=== REALISTIC MT5 BACKTEST $stamp ===" -ForegroundColor Cyan

# 1. MT5 must be connected
try {
    $st = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 15
    if (-not $st.connected) { throw "MT5 not connected" }
    if (-not $st.terminal_trade_allowed) { Write-Host "WARN: AutoTrading off (backtest still OK)" -ForegroundColor Yellow }
    Write-Host "MT5 OK server=$($st.server) equity=`$$([math]::Round($st.account.equity,2))"
} catch {
    Write-Host "FAIL: MT5 API unreachable - start Bilshenz-MT5-API task" -ForegroundColor Red
    exit 1
}

# 2. Ensure MT5 API task up
if (-not (Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue)) {
    schtasks /Run /TN "Bilshenz-MT5-API-Sys" 2>$null | Out-Null
    Start-Sleep -Seconds 15
}

Set-Location $Backend
$env:RISK_PCT = "0.01"
$env:STRATEGY_FREEZE = "1"

# 3. Realistic live-profile: Exness costs, MT5 equity, BSv3.2 frozen engine
$tsxCli = Join-Path $Backend "node_modules\tsx\dist\cli.mjs"
if (-not (Test-Path $tsxCli)) { throw "tsx missing at $tsxCli" }
$node = (Get-Command node.exe -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = "node.exe" }

$args = @(
    "`"$tsxCli`"",
    "scripts/run-xau-12mo-yahoo-backtest.ts",
    "--mt5-api=http://127.0.0.1:8765",
    "--exness",
    "--equity-from-mt5",
    "--risk-pct=1",
    "--realistic",
    "--broker-sl-pips=20",
    "--live-profile",
    "--out-suffix=realistic-mt5-$stamp"
)
$argLine = $args -join " "
Write-Host "Running: node $argLine"
cmd /c "node $argLine >> `"$logFile`" 2>&1"
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0 -and (Test-Path $logFile)) {
    Get-Content $logFile -Tail 20 | Write-Host
}

Write-Host ""
Write-Host "=== BACKTEST LOG (summary lines) ===" -ForegroundColor Cyan
Get-Content $logFile -ErrorAction SilentlyContinue | Select-String -Pattern "net|equity|trades|win|drawdown|profit|sharpe|PF|RESULT|ERROR|FAIL" -CaseSensitive:$false | Select-Object -Last 30 | ForEach-Object { $_.Line }

# 4. Copy latest report into validation data for institutional baseline refresh
$reports = Get-ChildItem $Backend -Recurse -Filter "*realistic-mt5-$stamp*" -ErrorAction SilentlyContinue
if ($reports) {
    foreach ($r in $reports) {
        Copy-Item $r.FullName (Join-Path $ReportDir $r.Name) -Force
        Write-Host "Report: $($r.FullName)"
    }
}

$baseline = Join-Path $Backend "scripts\forward-sim-baseline-30d.json"
if (Test-Path $baseline) {
    Copy-Item $baseline (Join-Path $ReportDir "forward-sim-baseline-30d.json") -Force
    Write-Host "Baseline refreshed: $baseline"
}

Write-Host "Full log: $logFile"
exit $exitCode
