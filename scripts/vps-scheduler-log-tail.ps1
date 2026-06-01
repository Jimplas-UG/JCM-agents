$log = "C:\logs\jcm\agent-scheduler.log"
$proc = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match "agent_scheduler" }
Write-Host "Processes matching agent_scheduler: $($proc.Count)"
$proc | ForEach-Object { Write-Host "  PID $($_.ProcessId) $($_.CommandLine.Substring(0, [Math]::Min(120, $_.CommandLine.Length)))" }
if (Test-Path $log) {
    Write-Host "`nLog tail:"
    Get-Content $log -Tail 40
} else { Write-Host "No log at $log" }
