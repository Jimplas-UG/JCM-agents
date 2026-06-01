$log = "C:\opt\bilshenz\backend\validation\data\forward-demo-log.jsonl"
if (-not (Test-Path $log)) { Write-Host "log missing: $log"; exit 1 }
$today = (Get-Date).ToString("yyyy-MM-dd")
$n = 0
Get-Content $log -Tail 5000 -EA SilentlyContinue | ForEach-Object {
    if ($_ -match $today -and $_ -match "ORDER_REJECTED") { $n++ }
}
Write-Host "ORDER_REJECTED on $today (last 5000 lines): $n"
