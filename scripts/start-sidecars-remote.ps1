Set-Location "C:\Users\Administrator\Documents\JCM agents\JCM-agents\infra\bot-integration"
$ErrorActionPreference = "Continue"
$here = Get-Location
$venvPython = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\.venv\Scripts\python.exe"

# Kill broken stub processes if any
Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match 'stub_execution_layer'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

foreach ($svc in @(@{Name='forward';Port=8083}, @{Name='watchdog';Port=8084})) {
    $listen = Get-NetTCPConnection -LocalPort $svc.Port -State Listen -ErrorAction SilentlyContinue
    if ($listen) { Write-Host "Port $($svc.Port) already up"; continue }
    Start-Process -FilePath $venvPython -ArgumentList "stub_execution_layer.py", $svc.Name -WorkingDirectory $here -WindowStyle Hidden
    Write-Host "Started $($svc.Name) on $($svc.Port)"
}
Start-Sleep -Seconds 8
$keys = @{8083='jcm_s930px6rvhanj7kt5qi8fy41ocdu';8084='jcm_caxs285n7flj0t4muord1z63hgbi'}
foreach ($port in 8083,8084) {
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:$port/health" -Headers @{Authorization="Bearer $($keys[$port])"} -UseBasicParsing -TimeoutSec 5
        Write-Host ":$port OK $($r.StatusCode)"
    } catch { Write-Host ":$port FAIL" }
}
