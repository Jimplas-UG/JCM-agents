# Backfill JCM trade_closed from MT5 deal history (no strategy changes).
$ErrorActionPreference = "Stop"
$Root = "C:\jcm-project"
$Backend = "$Root\backend"
$Py = "$Backend\.venv\Scripts\python.exe"
Copy-Item "$Root\.env" "$Backend\.env" -Force
Set-Location $Backend
$env:PYTHONPATH = $Backend
& $Py -m app.scripts.backfill_trade_closed_from_mt5 @args
