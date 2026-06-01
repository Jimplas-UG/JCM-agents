# Set Telegram env on VPS .env files (run ON VPS; token passed as args — never commit).
param(
    [Parameter(Mandatory = $true)][string]$BotToken,
    [string]$ChatId = ""
)
$ErrorActionPreference = "Stop"
$paths = @(
    "C:\jcm-project\.env",
    "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env",
    "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\.env"
)
function Set-EnvLine($file, $key, $value) {
    if (-not (Test-Path $file)) { return }
    $lines = Get-Content $file -EA SilentlyContinue
    $out = @()
    $found = $false
    foreach ($line in $lines) {
        if ($line -match "^\s*$key=") {
            $out += "$key=$value"
            $found = $true
        } else { $out += $line }
    }
    if (-not $found) { $out += "$key=$value" }
    Set-Content -Path $file -Value $out -Encoding UTF8
}

if (-not $ChatId) {
    try {
        $uri = "https://api.telegram.org/bot$BotToken/getUpdates?limit=5"
        $r = Invoke-RestMethod -Uri $uri -TimeoutSec 15
        $chat = $r.result | ForEach-Object { $_.message.chat.id } | Select-Object -Last 1
        if ($chat) { $ChatId = [string]$chat; Write-Host "Resolved chat_id from getUpdates" }
    } catch { Write-Host "getUpdates failed: $_" }
}

foreach ($p in $paths) {
    if (Test-Path $p) {
        Set-EnvLine $p "TELEGRAM_BOT_TOKEN" $BotToken
        if ($ChatId) { Set-EnvLine $p "TELEGRAM_CHAT_ID" $ChatId }
        Set-EnvLine $p "EXECUTIVE_BRIEFING_TELEGRAM_NOTIFY" "true"
        Write-Host "Updated $p"
    }
}
if (-not $ChatId) {
    Write-Host "Token saved. CHAT_ID missing: open https://t.me/BilshenzBot , tap Start, send any message, then run:"
    Write-Host "  powershell -File C:\Users\Administrator\vps-resolve-telegram-chat.ps1"
    exit 2
}
Write-Host "Telegram configured (token + chat_id set, not printed)."
