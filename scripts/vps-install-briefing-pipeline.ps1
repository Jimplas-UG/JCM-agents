# Run ON VPS: unattended briefing tasks (SYSTEM - no interactive logon required).
$ErrorActionPreference = "Stop"
$LogDir = "C:\logs\jcm"
$ScriptsDir = "C:\jcm\scripts"
$Root = "C:\jcm-project"

if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $ScriptsDir)) { New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null }

$toCopy = @(
    "vps-briefing-common.ps1",
    "vps-send-briefing-telegram.ps1",
    "vps-briefing-backup.ps1",
    "vps-briefing-startup-catchup.ps1",
    "run-briefing-primary.bat",
    "run-briefing-backup.bat",
    "run-briefing-startup-catchup.bat"
)
foreach ($f in $toCopy) {
    $src = Join-Path $Root "scripts\$f"
    if (-not (Test-Path $src)) { $src = "C:\Users\Administrator\$f" }
    if (-not (Test-Path $src)) { throw "Missing $f" }
    Copy-Item $src (Join-Path $ScriptsDir $f) -Force
    Copy-Item $src "C:\Users\Administrator\$f" -Force
}

# SYSTEM must read .env and write logs
if (Test-Path "$Root\.env") {
    icacls "$Root\.env" /grant "NT AUTHORITY\SYSTEM:(R)" /Q 2>$null | Out-Null
}
icacls $LogDir /grant "NT AUTHORITY\SYSTEM:(M)" /Q 2>$null | Out-Null
icacls "$Root\backend\.venv" /grant "NT AUTHORITY\SYSTEM:(OI)(CI)RX" /T /Q 2>$null | Out-Null
icacls $ScriptsDir /grant "NT AUTHORITY\SYSTEM:(OI)(CI)RX" /T /Q 2>$null | Out-Null

function Register-DailyTaskSystem($name, $time, $batName) {
    $bat = Join-Path $ScriptsDir $batName
    cmd /c "schtasks /End /TN `"$name`" 2>nul"
    cmd /c "schtasks /Delete /TN `"$name`" /F 2>nul"
    $tr = "cmd.exe /c `"$bat`""
    schtasks /Create /TN $name /TR $tr /SC DAILY /ST $time /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create task $name" }
    Write-Host "Registered $name at $time (SYSTEM via $batName)"
}

function Register-OnStartTaskSystem($name, $batName) {
    $bat = Join-Path $ScriptsDir $batName
    cmd /c "schtasks /End /TN `"$name`" 2>nul"
    cmd /c "schtasks /Delete /TN `"$name`" /F 2>nul"
    $tr = "cmd.exe /c `"$bat`""
    schtasks /Create /TN $name /TR $tr /SC ONSTART /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create task $name" }
    Write-Host "Registered $name ONSTART (SYSTEM via $batName)"
}

Register-DailyTaskSystem "JCM-Daily-Executive-Briefing" "09:00" "run-briefing-primary.bat"
Register-DailyTaskSystem "JCM-Briefing-Telegram-Backup" "09:15" "run-briefing-backup.bat"
Register-OnStartTaskSystem "JCM-Briefing-Startup-Catchup" "run-briefing-startup-catchup.bat"

Write-Host ""
schtasks /Query /TN JCM-Daily-Executive-Briefing /V /FO LIST | findstr /I "TaskName Run As Last Run Next Logon"
schtasks /Query /TN JCM-Briefing-Telegram-Backup /V /FO LIST | findstr /I "TaskName Run As Last Run Next Logon"
Write-Host "Logs: $LogDir\daily-briefing-telegram.log"
