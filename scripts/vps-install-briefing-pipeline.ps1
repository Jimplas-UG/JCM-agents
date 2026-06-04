# Run ON VPS: register primary + backup briefing tasks (09:00 and 09:15 local).
$ErrorActionPreference = "Stop"
$LogDir = "C:\logs\jcm"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

$primary = "C:\Users\Administrator\vps-send-briefing-telegram.ps1"
$backup = "C:\Users\Administrator\vps-briefing-backup.ps1"
foreach ($p in @($primary, $backup)) {
    if (-not (Test-Path $p)) { throw "Missing $p - deploy scripts to VPS first" }
}

function Register-DailyTask($name, $time, $script) {
    cmd /c "schtasks /End /TN `"$name`" 2>nul"
    cmd /c "schtasks /Delete /TN `"$name`" /F 2>nul"
    $tr = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
    $null = schtasks /Create /TN $name /TR $tr /SC DAILY /ST $time /RU Administrator /RL HIGHEST /F 2>&1
    if ($LASTEXITCODE -ne 0) {
        schtasks /Create /TN $name /TR $tr /SC DAILY /ST $time /RL HIGHEST /F | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { throw "Failed to create task $name" }
    Write-Host "Registered $name at $time"
}

Register-DailyTask "JCM-Daily-Executive-Briefing" "09:00" $primary
Register-DailyTask "JCM-Briefing-Telegram-Backup" "09:15" $backup

Write-Host ""
Write-Host "Briefing pipeline tasks:"
schtasks /Query /TN JCM-Daily-Executive-Briefing /FO LIST | findstr /I "TaskName Status Next"
schtasks /Query /TN JCM-Briefing-Telegram-Backup /FO LIST | findstr /I "TaskName Status Next"
Write-Host "Logs: $LogDir\daily-briefing-telegram.log"
