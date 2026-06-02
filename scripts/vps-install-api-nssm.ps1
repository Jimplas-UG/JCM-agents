# Install JCM API as NSSM Windows service (persistent Mission Control).
$ErrorActionPreference = "Stop"
$NssmExe = "C:\jcm\nssm\nssm.exe"
$Backend = "C:\jcm-project\backend"
$Py = "$Backend\.venv\Scripts\python.exe"
if (-not (Test-Path $Py)) {
    $Backend = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend"
    $Py = "$Backend\.venv\Scripts\python.exe"
}

New-Item -ItemType Directory -Force -Path C:\jcm, C:\jcm\logs | Out-Null
@(
    "Set-Location `"$Backend`"",
    "Copy-Item `"C:\jcm-project\.env`" .env -Force -EA SilentlyContinue",
    "& `"$Py`" -m uvicorn app.main:app --host 0.0.0.0 --port 8000"
) -join "`r`n" | Set-Content C:\jcm\run-api.ps1 -Encoding UTF8

if (-not (Test-Path $NssmExe)) {
    $zip = "$env:TEMP\nssm.zip"
    Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
    New-Item -ItemType Directory -Force -Path C:\jcm\nssm | Out-Null
    Copy-Item "$env:TEMP\nssm-2.24\win64\nssm.exe" $NssmExe -Force
}

Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.CommandLine -match "jcm-api-keepalive|uvicorn app\.main:app"
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
schtasks /Change /TN "JCM-API-Keepalive" /DISABLE 2>$null | Out-Null

$svc = "JCMAPI"
$existing = Get-Service $svc -EA SilentlyContinue
if ($existing) {
    & $NssmExe stop $svc confirm 2>$null
    Start-Sleep 3
    & $NssmExe remove $svc confirm 2>$null
    Start-Sleep 2
}

$ps = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
& $NssmExe install $svc $ps "-NoProfile -ExecutionPolicy Bypass -File C:\jcm\run-api.ps1"
& $NssmExe set $svc AppDirectory $Backend
& $NssmExe set $svc AppStdout "C:\jcm\logs\jcm-api.out.log"
& $NssmExe set $svc AppStderr "C:\jcm\logs\jcm-api.err.log"
& $NssmExe set $svc AppExit Default Restart
& $NssmExe set $svc AppRestartDelay 5000
& $NssmExe set $svc Start SERVICE_AUTO_START
& $NssmExe start $svc

foreach ($p in 8000) {
    $n = "JCM-Port-$p"
    if (-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $n -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -Profile Any | Out-Null
    }
}
if (-not (Get-NetFirewallRule -DisplayName "JCM-Python-API" -EA SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "JCM-Python-API" -Direction Inbound -Action Allow -Program $Py -Profile Any | Out-Null
}

Start-Sleep -Seconds 20
$h = Invoke-RestMethod "http://127.0.0.1:8000/health" -TimeoutSec 15
if ($h.status -ne "healthy") { throw "JCMAPI service unhealthy" }
Write-Host "JCMAPI running"
