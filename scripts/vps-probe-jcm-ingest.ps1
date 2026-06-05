$envFile = "C:\ProgramData\Bilshenz\tradingbot.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), "Process")
        }
    }
}
$url = $env:JCM_INGEST_WEBHOOK_URL
$secret = if ($env:JCM_WEBHOOK_SECRET) { $env:JCM_WEBHOOK_SECRET } else { $env:EVENT_WEBHOOK_SECRET }
Write-Host "ingest_url=$url"
$body = @{
    event_type = "trade_executed"
    payload = @{
        event_id = "audit-probe-$(Get-Date -Format 'yyyyMMddHHmmss')"
        event_type = "trade_executed"
        symbol = "XAUUSD"
        direction = "long"
        lot_size = 0.01
        entry_price = 3350.0
        filled_price = 3350.0
        outcome = "open"
        bsv32_version = "3.2"
        raw_payload = @{ mt5_ticket = 12345; setup = "audit" }
    }
} | ConvertTo-Json -Depth 6
try {
    $r = Invoke-WebRequest -Uri $url -Method POST -Headers @{
        "Content-Type" = "application/json"
        "X-Webhook-Secret" = $secret
    } -Body $body -UseBasicParsing -TimeoutSec 15
    Write-Host "PASS ingest HTTP $($r.StatusCode) $($r.Content)"
} catch {
    $resp = $_.Exception.Response
    if ($resp) {
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        Write-Host "FAIL ingest HTTP $([int]$resp.StatusCode) $($reader.ReadToEnd())"
    } else {
        Write-Host "FAIL ingest $($_.Exception.Message)"
    }
}
