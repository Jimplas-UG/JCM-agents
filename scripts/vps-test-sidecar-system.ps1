$Py = "C:\jcm-project\backend\.venv\Scripts\python.exe"
$Dir = "C:\jcm-project\infra\bot-integration"
Set-Location $Dir
& $Py stub_execution_layer.py forward *> C:\jcm\logs\sidecar-system-test.log 2>&1
