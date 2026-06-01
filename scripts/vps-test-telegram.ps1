# Send test CEO-briefing-style ping (run on VPS).
$ErrorActionPreference = "Stop"
$envPath = "C:\jcm-project\.env"
if (-not (Test-Path $envPath)) { $envPath = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env" }
$tok = $null; $chat = $null
Get-Content $envPath | ForEach-Object {
    if ($_ -match '^\s*TELEGRAM_BOT_TOKEN=(.+)$') { $tok = $Matches[1].Trim() }
    if ($_ -match '^\s*TELEGRAM_CHAT_ID=(.+)$') { $chat = $Matches[1].Trim() }
}
if (-not $tok -or -not $chat) { throw "Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID first" }
$text = @"
*JIMPLAS CAPITAL MANAGEMENT*
*Daily Executive Intelligence Brief*

Good morning, *Billy Jimplas* — Global CEO

Your executive briefing is ready for review (connectivity test).

*Mission posture:* operational
Please open Mission Control for the full synthesis.

http://104.194.140.203:8000/mission-control

— JCM CEO Copilot · BSv3.2 Supervisory Platform
"@
$body = @{ chat_id = $chat; text = $text; parse_mode = "Markdown" } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$tok/sendMessage" -ContentType "application/json" -Body $body -TimeoutSec 15 | Out-Null
Write-Host "Test message sent."
