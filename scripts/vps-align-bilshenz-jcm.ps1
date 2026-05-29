# Align VPS with Bilshenz deploy (C:\opt\bilshenz) + JCM agents — infra only, no strategy changes.
# Run on VPS as Administrator:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\vps-align-bilshenz-jcm.ps1
$ErrorActionPreference = "Continue"

$Bilshenz = "C:\opt\bilshenz"
$Win = Join-Path $Bilshenz "deploy\windows"
$JcmReal = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Jcm = "C:\jcm-project"
if (-not (Test-Path $Jcm)) {
    cmd /c "mklink /J `"$Jcm`" `"$JcmReal`""
    Write-Host "Junction: $Jcm -> $JcmReal"
}
$Nssm = "C:\jcm\nssm\nssm.exe"

Write-Host "=== Align Bilshenz + JCM (official stack) ===" -ForegroundColor Cyan

# --- Remove custom NSSM services that fight Bilshenz scheduled tasks ---
if (Test-Path $Nssm) {
    foreach ($svc in @("BilshenzMT5", "JCMDashboard", "JCMSidecarFwd", "JCMSidecarWD", "JCMSidecars", "JCMKeepalive", "JCMAPI")) {
        if (Get-Service $svc -EA SilentlyContinue) {
            & $Nssm stop $svc confirm 2>$null
            Start-Sleep -Seconds 2
            & $Nssm remove $svc confirm 2>$null
            Write-Host "Removed NSSM service $svc"
        }
    }
}

# --- Disable JCM custom keepalive/watchdog (use Bilshenz tasks instead) ---
foreach ($tn in @("JCM-Keepalive-Min", "JCM-Stack-Watchdog", "Bilshenz-DirectStart")) {
    schtasks /Change /TN $tn /DISABLE 2>$null
}

# --- Bilshenz Interactive tasks (optional; may fail headless - Sys tasks are primary) ---
if (Test-Path (Join-Path $Win "install-scheduled-tasks.ps1")) {
    try {
        & (Join-Path $Win "install-scheduled-tasks.ps1") -AppDir $Bilshenz -ErrorAction Stop
    } catch {
        Write-Host "Note: Bilshenz interactive task registration skipped (use *-Sys tasks on headless VPS)"
    }
}

# --- SYSTEM account access to JCM junction (required for dashboard/sidecars as SYSTEM) ---
icacls $Jcm /grant "SYSTEM:(OI)(CI)RX" /T /C 2>$null | Out-Null
icacls "C:\jcm" /grant "SYSTEM:(OI)(CI)F" /T /C 2>$null | Out-Null

# --- Patched watchdog (infra resilience only - forward-bot detection fix) ---
$watchdogSrc = Join-Path $Jcm "watchdog.vps.ts"
if (-not (Test-Path $watchdogSrc)) { $watchdogSrc = Join-Path $Jcm "scripts\watchdog.vps.ts" }
$watchdogDst = Join-Path $Bilshenz "deploy\watchdog.ts"
if (Test-Path $watchdogSrc) {
    Copy-Item $watchdogSrc $watchdogDst -Force
    Write-Host "Updated Bilshenz watchdog.ts (infra patch)"
}

# --- Enable Bilshenz-Watchdog with patched logic ---
schtasks /Change /TN "Bilshenz-Watchdog" /ENABLE 2>$null

# --- Enable JCM boot task (uses vps-restart-all.ps1 - non-destructive) ---
schtasks /Change /TN "JCM-Stack-Startup" /ENABLE 2>$null

# --- Firewall: dashboard external on 8080 (3000 blocked upstream) ---
foreach ($p in 8080, 8000, 8765, 8791) {
    $n = "JCM-Port-$p"
    if (-not (Get-NetFirewallRule -DisplayName $n -EA SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $n -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p | Out-Null
    }
}

# --- Clear forward-bot failsafe if MT5 is healthy ---
$sf = "C:\logs\tradingbot\safety-state.json"
try {
    $mt5 = Invoke-RestMethod "http://127.0.0.1:8765/api/status" -TimeoutSec 5
    if ($mt5.connected -and (Test-Path $sf)) {
        $s = Get-Content $sf -Raw | ConvertFrom-Json
        $s.failsafe = $false; $s.failsafeReason = $null; $s.consecutiveApiFailures = 0
        $s | ConvertTo-Json | Set-Content $sf -Encoding UTF8
        Write-Host "Failsafe cleared"
    }
} catch {}

if (-not (Test-Path "C:\jcm")) { New-Item -ItemType Directory -Force -Path "C:\jcm" | Out-Null }
@'
Set-Location "C:\jcm-project\frontend\.next\standalone"
$env:PORT = "8080"
$env:HOSTNAME = "0.0.0.0"
$staticSrc = "C:\jcm-project\frontend\.next\static"
$staticDst = "C:\jcm-project\frontend\.next\standalone\.next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}
& "C:\Program Files\nodejs\node.exe" server.js
'@ | Set-Content "C:\jcm\run-dashboard-8080.ps1" -Encoding UTF8

# --- Persistent SYSTEM tasks (headless VPS - matches Bilshenz + JCM deploy scripts) ---
$sysTasks = Join-Path $Jcm "scripts\vps-install-system-tasks.ps1"
if (Test-Path $sysTasks) {
    & $sysTasks
} else {
    Write-Host "WARN: vps-install-system-tasks.ps1 missing - starting tasks manually"
    foreach ($tn in @(
        "Bilshenz-MT5-API-Sys", "Bilshenz-DeskAPI-Sys", "Bilshenz-ForwardBot-Sys",
        "Bilshenz-Watchdog-Sys", "JCM-API-Sys", "JCM-Dashboard-Sys", "JCM-Sidecars-Sys"
    )) {
        schtasks /Run /TN $tn 2>$null
    }
    Start-Sleep -Seconds 30
}

# --- Boot orchestration (Bilshenz official) ---
$boot = Join-Path $Win "boot-start-bilshenz.ps1"
if (Test-Path $boot) {
    Start-Process powershell.exe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File",$boot,"-AppDir",$Bilshenz -WindowStyle Hidden
    Write-Host "Triggered boot-start-bilshenz.ps1"
}

# --- Verify ---
if (Test-Path "C:\Users\Administrator\vps-live-test.ps1") {
    & "C:\Users\Administrator\vps-live-test.ps1"
}

Write-Host 'Bilshenz: MT5 :8765 | Desk :8791 | Forward bot + watchdog tasks' -ForegroundColor Green
Write-Host 'JCM:     API :8000 | Dashboard http://104.194.140.203:8080 | Sidecars :8083/:8084' -ForegroundColor Green
