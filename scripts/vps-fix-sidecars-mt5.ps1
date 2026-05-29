# Fix sidecars (direct python NSSM) and MT5 service (kill orphan, resume NSSM)
$ErrorActionPreference = "Continue"
$Nssm = "C:\jcm\nssm\nssm.exe"
$Py = "C:\jcm-project\backend\.venv\Scripts\python.exe"
$SidecarDir = "C:\jcm-project\infra\bot-integration"

function Kill-Port($port) {
    Get-NetTCPConnection -LocalPort $port -State Listen -EA SilentlyContinue | ForEach-Object {
        Write-Host "Kill pid $($_.OwningProcess) on :$port"
        Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue
    }
}

function Install-Sidecar($name, $mode, $port, $log) {
    Kill-Port $port
    if (Get-Service $name -EA SilentlyContinue) {
        & $Nssm stop $name confirm 2>$null
        Start-Sleep 2
        & $Nssm remove $name confirm 2>$null
        Start-Sleep 1
    }
    & $Nssm install $name $Py "stub_execution_layer.py" $mode
    & $Nssm set $name AppDirectory $SidecarDir
    & $Nssm set $name AppStdout "C:\jcm\logs\$log.out.log"
    & $Nssm set $name AppStderr "C:\jcm\logs\$log.err.log"
    & $Nssm set $name AppRotateFiles 1
    & $Nssm set $name Start SERVICE_AUTO_START
    & $Nssm start $name
    Start-Sleep 4
    Write-Host "$name -> $((Get-Service $name).Status) nssm=$(& $Nssm status $name)"
}

# Sidecars
Install-Sidecar "JCMSidecarFwd" "forward" 8083 "sidecar-fwd"
Install-Sidecar "JCMSidecarWD" "watchdog" 8084 "sidecar-wd"

# MT5: if NSSM paused/stopped but orphan python holds :8765, hand port to service
$mt5Svc = Get-Service BilshenzMT5 -EA SilentlyContinue
if ($mt5Svc) {
    $nssmSt = & $Nssm status BilshenzMT5 2>$null
    if ($nssmSt -match "PAUSED|STOPPED") {
        $orphan = Get-NetTCPConnection -LocalPort 8765 -State Listen -EA SilentlyContinue
        if ($orphan) {
            Write-Host "MT5 orphan pid $($orphan.OwningProcess) - stopping for NSSM"
            Stop-Process -Id $orphan.OwningProcess -Force -EA SilentlyContinue
            Start-Sleep 3
        }
        & $Nssm continue BilshenzMT5 2>$null
        & $Nssm start BilshenzMT5 2>$null
        Start-Sleep 8
        Write-Host "BilshenzMT5 -> $((Get-Service BilshenzMT5).Status) nssm=$(& $Nssm status BilshenzMT5)"
    }
}

& "C:\Users\Administrator\vps-live-test.ps1"
