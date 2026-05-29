$ErrorActionPreference = "Stop"
$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "Administrator" -LogonType Interactive -RunLevel Highest

function Reg([string]$name, [string]$argLine) {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass $argLine"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
    schtasks /Run /TN $name 2>&1 | Out-Null
    Write-Host "Started $name"
}

# Disable conflicting watchdogs
schtasks /Change /TN "JCM-Stack-Watchdog" /DISABLE 2>$null
schtasks /Change /TN "Bilshenz-Watchdog" /DISABLE 2>$null

Reg "Bilshenz-MT5-API-Adm" '-File "C:\opt\bilshenz\deploy\windows\run-mt5-api.ps1" -AppDir "C:\opt\bilshenz"'
Start-Sleep 25
Reg "JCM-Dashboard-Adm" "-File `"$Jcm\scripts\run-jcm-dashboard.ps1`""
Start-Sleep 10
Reg "JCM-Sidecars-Adm" "-File `"$Jcm\scripts\run-jcm-sidecars.ps1`""
Start-Sleep 8
& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1"

foreach ($p in 3000,8000) {
    $n = if ($p -eq 3000) { "JCM-Dashboard-3000" } else { "JCM-API-8000" }
    if (-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $n -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
    }
}
Start-Sleep 20
& "C:\Users\Administrator\vps-live-test.ps1"
