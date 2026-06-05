$Backend = "C:\jcm-project\backend"
Copy-Item "C:\jcm-project\.env" "$Backend\.env" -Force
Set-Location $Backend
$env:PYTHONPATH = $Backend
& "$Backend\.venv\Scripts\python.exe" -m app.scripts.probe_ingest_direct
