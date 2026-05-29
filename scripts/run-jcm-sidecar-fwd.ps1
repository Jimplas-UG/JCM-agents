$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location (Join-Path $Root "infra\bot-integration")
& (Join-Path $Root "backend\.venv\Scripts\python.exe") stub_execution_layer.py forward
