# Bring Mission Control API up and verify (run on VPS via scp + ssh).
$ErrorActionPreference = "Continue"
$Backend = "C:\jcm-project\backend"
$Py = "$Backend\.venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
    $Backend = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend"
    $Py = "$Backend\.venv\Scripts\python.exe"
}

schtasks /Change /TN "JCM-API-Keepalive" /DISABLE 2>$null | Out-Null
Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "jcm-api-keepalive"
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }

if (-not (Get-NetTCPConnection -LocalPort 8000 -State Listen -EA SilentlyContinue)) {
    Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.CommandLine -match "uvicorn app\.main:app"
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
    Start-Sleep 2
    $args = "-m uvicorn app.main:app --host 0.0.0.0 --port 8000"
    $cmd = "cd /d `"$Backend`" && start `"JCMAPI`" /MIN `"$Py`" $args"
    Start-Process cmd.exe -ArgumentList "/c", $cmd -WindowStyle Hidden
    Start-Sleep 20
}

foreach ($p in 8000) {
    $n = "JCM-Port-$p"
    if (-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $n -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
    }
}

$h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 15
if ($h.status -ne "healthy") { throw "API unhealthy" }
Write-Host "OK http://104.194.140.203:8000/mission-control"
