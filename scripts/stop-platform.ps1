#Requires -Version 5.1
<#
.SYNOPSIS
  Stop JCM platform processes on Windows.
#>
Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object {
    $_.CommandLine -match 'uvicorn app.main' -or $_.CommandLine -match 'app.workers.agent_scheduler'
} | ForEach-Object {
    Write-Host "Stopping PID $($_.ProcessId): python"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {
    $_.CommandLine -match 'next start' -or $_.CommandLine -match 'npm start'
} | ForEach-Object {
    Write-Host "Stopping PID $($_.ProcessId): node (dashboard)"
    Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

Write-Host "Platform stopped."
