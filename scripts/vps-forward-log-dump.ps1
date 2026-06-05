foreach ($f in @(
    "C:\logs\tradingbot\forward-bot.err.log",
    "C:\logs\tradingbot\forward-bot.out.log"
)) {
    if (Test-Path $f) {
        Write-Host "=== $f (tail 20) ==="
        Get-Content $f -Tail 20
    } else {
        Write-Host "missing $f"
    }
}
