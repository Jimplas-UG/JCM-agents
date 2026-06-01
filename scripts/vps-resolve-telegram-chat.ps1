# Resolve TELEGRAM_CHAT_ID from getUpdates (run on VPS after messaging @BilshenzBot).
$ErrorActionPreference = "Stop"
$envPath = "C:\jcm-project\.env"
if (-not (Test-Path $envPath)) { $envPath = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env" }
$tok = $null
Get-Content $envPath | ForEach-Object {
    if ($_ -match '^\s*TELEGRAM_BOT_TOKEN=(.+)$') { $tok = $Matches[1].Trim() }
}
if (-not $tok) { throw "TELEGRAM_BOT_TOKEN not in $envPath" }
$r = Invoke-RestMethod "https://api.telegram.org/bot$tok/getUpdates?limit=10" -TimeoutSec 15
$chat = $r.result | ForEach-Object { $_.message.chat.id } | Select-Object -Last 1
if (-not $chat) { throw "No messages yet - message @BilshenzBot first" }
& "C:\Users\Administrator\vps-set-telegram-env.ps1" -BotToken $tok -ChatId ([string]$chat)
Write-Host "chat_id resolved and saved."
