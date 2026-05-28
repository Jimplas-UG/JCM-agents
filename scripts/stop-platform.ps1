#Requires -Version 5.1
<#
.SYNOPSIS
  Stop JCM platform processes on Windows.
#>
$ErrorActionPreference = "Continue"

function Stop-ListenPort([int]$port, [string]$label) {
    $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($conn) {
        Write-Host "Stopping $label on port $port (PID $($conn.OwningProcess))"
        Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match 'uvicorn app\.main' -or $_.CommandLine -match 'app\.workers\.agent_scheduler'
} | ForEach-Object {
    Write-Host "Stopping PID $($_.ProcessId): python (JCM)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match 'JCM-agents\\frontend' -or
    $_.CommandLine -match 'jcm-bsv32-dashboard' -or
    ($_.CommandLine -match 'next' -and $_.CommandLine -match 'start')
} | ForEach-Object {
    Write-Host "Stopping PID $($_.ProcessId): node (dashboard)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Stop-ListenPort 3000 "dashboard"
Stop-ListenPort 8000 "API"

Write-Host "Platform stopped."
