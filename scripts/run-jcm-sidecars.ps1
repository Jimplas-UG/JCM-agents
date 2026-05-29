$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$here = Join-Path $Root "infra\bot-integration"
$py = Join-Path $Root "backend\.venv\Scripts\python.exe"
Set-Location $here
Start-Process $py -ArgumentList "stub_execution_layer.py","forward" -WorkingDirectory $here -WindowStyle Hidden
Start-Process $py -ArgumentList "stub_execution_layer.py","watchdog" -WorkingDirectory $here -WindowStyle Hidden
while ($true) { Start-Sleep -Seconds 3600 }
