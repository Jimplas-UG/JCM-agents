Get-Content C:\logs\tradingbot\forward-bot.err.log -Tail 30 -EA SilentlyContinue
Write-Host "--- out ---"
Get-Content C:\logs\tradingbot\forward-bot.out.log -Tail 10 -EA SilentlyContinue
