$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Backend = Join-Path $Root "backend"
Copy-Item (Join-Path $Root ".env") (Join-Path $Backend ".env") -Force -EA SilentlyContinue
Set-Location $Backend
$py = Join-Path $Backend ".venv\Scripts\python.exe"
if (-not (Test-Path $py)) { $py = "python.exe" }
& $py -m uvicorn app.main:app --host 0.0.0.0 --port 8000
