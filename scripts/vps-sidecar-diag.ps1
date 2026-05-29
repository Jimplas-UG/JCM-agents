$ErrorActionPreference = "Continue"
$here = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\infra\bot-integration"
$venv = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\.venv\Scripts\python.exe"

Write-Host "=== Sidecar diagnostics ==="
Write-Host "Venv exists: $(Test-Path $venv)"

& $venv -m pip show fastapi uvicorn httpx 2>&1 | Select-String "Name:|Version:"

Write-Host "`nPorts:"
Get-NetTCPConnection -LocalPort 8083,8084 -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  :$($_.LocalPort) PID $($_.OwningProcess)"
}

Write-Host "`nPython stub processes:"
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.CommandLine -match 'stub_execution_layer'
} | ForEach-Object { Write-Host $_.CommandLine }

Write-Host "`nManual stub test (5s):"
$stub = Join-Path $here "stub_execution_layer.py"
$p = Start-Process -FilePath $venv -ArgumentList $stub, "forward" -WorkingDirectory $here -PassThru -RedirectStandardError "$env:TEMP\stub-test.err" -RedirectStandardOutput "$env:TEMP\stub-test.out" -WindowStyle Hidden
Start-Sleep -Seconds 5
if (Get-NetTCPConnection -LocalPort 8083 -State Listen -ErrorAction SilentlyContinue) {
    Write-Host "8083 listening after manual start"
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:8083/health" -Headers @{ Authorization = "Bearer jcm_s930px6rvhanj7kt5qi8fy41ocdu" } -UseBasicParsing
        Write-Host "Health: $($r.StatusCode) $($r.Content)"
    } catch { Write-Host "Health fail: $($_.Exception.Message)" }
} else {
    Write-Host "8083 NOT listening"
    if (Test-Path "$env:TEMP\stub-test.err") { Get-Content "$env:TEMP\stub-test.err" }
    if (Test-Path "$env:TEMP\stub-test.out") { Get-Content "$env:TEMP\stub-test.out" }
}
Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
