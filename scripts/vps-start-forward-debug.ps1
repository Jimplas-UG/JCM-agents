$Backend = 'C:\opt\bilshenz\backend'
$ef = 'C:\ProgramData\Bilshenz\tradingbot.env'
. 'C:\opt\bilshenz\deploy\windows\Import-TradingBotEnv.ps1'
Set-Location $Backend
$env:PRODUCTION_MODE = '1'
$env:PRODUCTION_NO_EXPIRY = '1'
$env:STRATEGY_FREEZE = '1'
$tsxCli = Join-Path $Backend 'node_modules\tsx\dist\cli.mjs'
Write-Host "tsx exists: $(Test-Path $tsxCli)"
Write-Host "Running 8s test..."
$p = Start-Process -FilePath 'node.exe' -ArgumentList @($tsxCli, 'scripts/run-forward-demo-30d.ts') -WorkingDirectory $Backend -PassThru -NoNewWindow -RedirectStandardError 'C:\Users\Administrator\forward-test.err' -RedirectStandardOutput 'C:\Users\Administrator\forward-test.out'
Start-Sleep -Seconds 8
if (-not $p.HasExited) {
    Write-Host "Still running PID $($p.Id) - good"
    Stop-Process -Id $p.Id -Force
} else {
    Write-Host "Exited code $($p.ExitCode)"
}
Write-Host "--- stdout ---"
Get-Content 'C:\Users\Administrator\forward-test.out' -ErrorAction SilentlyContinue
Write-Host "--- stderr ---"
Get-Content 'C:\Users\Administrator\forward-test.err' -ErrorAction SilentlyContinue
