Write-Host "=== Ports ==="
Get-NetTCPConnection -LocalPort 3000,8083,8084,8765,8791,8000 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ":$($_.LocalPort) PID $($_.OwningProcess)" }
Write-Host "`n=== Stub processes ==="
Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -like '*stub*' } | ForEach-Object { Write-Host $_.ProcessId $_.CommandLine }
Write-Host "`n=== Webhook test ==="
try {
  $r = Invoke-WebRequest -Uri "http://127.0.0.1:8000/ingest/event" -Method POST -Headers @{"X-Webhook-Secret"="26nvWoyYBrR4GMuNZeaFLJP1OXc75Idi"} -Body '{"event_type":"trade_executed","payload":{"event_id":"t1"}}' -ContentType "application/json" -UseBasicParsing
  Write-Host "OK $($r.StatusCode)"
} catch { Write-Host "FAIL $($_.Exception.Message)" }
