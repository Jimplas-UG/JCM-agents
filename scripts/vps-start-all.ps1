$ErrorActionPreference = "Continue"
function PortUp($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue) }

& "C:\Users\Administrator\vps-write-short-scripts.ps1"

$starts = @(
    @{Name="MT5"; Script="C:\jcm\run-mt5.ps1"; Port=8765},
    @{Name="API"; Script="C:\jcm\run-api.ps1"; Port=8000},
    @{Name="Dashboard"; Script="C:\jcm\run-dashboard.ps1"; Port=3000},
    @{Name="Sidecars"; Script="C:\jcm\run-sidecars.ps1"; Port=8083}
)
foreach ($s in $starts) {
    if (PortUp $s.Port) { Write-Host "$($s.Name) already on :$($s.Port)"; continue }
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$s.Script -WindowStyle Hidden
    Write-Host "Started $($s.Name)"
    Start-Sleep -Seconds 12
}
if (-not (Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'run-forward-demo' })) {
    & "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"
}
Start-Sleep 15
& "C:\Users\Administrator\vps-live-test.ps1"
