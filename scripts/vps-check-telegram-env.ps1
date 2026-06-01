$envPath = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env"
if (-not (Test-Path $envPath)) { $envPath = "C:\jcm-project\.env" }
$tok = $false
$chat = $false
Get-Content $envPath -EA SilentlyContinue | ForEach-Object {
    if ($_ -match '^\s*TELEGRAM_BOT_TOKEN=(.+)$' -and $Matches[1].Trim()) { $tok = $true }
    if ($_ -match '^\s*TELEGRAM_CHAT_ID=(.+)$' -and $Matches[1].Trim()) { $chat = $true }
}
Write-Host "TELEGRAM_BOT_TOKEN set: $tok"
Write-Host "TELEGRAM_CHAT_ID set: $chat"
Write-Host "Executive briefing 09:00 Africa/Kampala when agent_scheduler is running."
