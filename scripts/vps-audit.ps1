# Institutional VPS audit — JCM platform + Bilshenz + sidecars
$ErrorActionPreference = "Continue"
$Report = @()
function Add-R($section, $status, $detail) { $script:Report += [pscustomobject]@{ Section = $section; Status = $status; Detail = $detail } }

Write-Host "=== JCM VPS AUDIT $(Get-Date -Format o) ===" -ForegroundColor Cyan

# RAM
$os = Get-CimInstance Win32_OperatingSystem
$freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
Add-R "System" "INFO" "RAM free ${freeGB}GB / ${totalGB}GB"

# Windows services
foreach ($svc in @("postgresql-x64-17", "Memurai")) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s) { Add-R "Service" $(if ($s.Status -eq "Running") { "OK" } else { "FAIL" }) "$svc = $($s.Status)" }
    else { Add-R "Service" "FAIL" "$svc not found" }
}

# Ports
$ports = @(3000, 5432, 6379, 8000, 8083, 8084, 8765, 8791)
foreach ($p in $ports) {
    $listen = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    Add-R "Port" $(if ($listen) { "OK" } else { "DOWN" }) ":$p"
}

# Paths
$paths = @{
    "JCM" = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
    "Bilshenz" = "C:\opt\bilshenz"
    "Cursor" = "$env:LOCALAPPDATA\Programs\cursor"
    "DotCursor" = "$env:USERPROFILE\.cursor"
}
foreach ($k in $paths.Keys) {
    Add-R "Path" $(if (Test-Path $paths[$k]) { "EXISTS" } else { "MISSING" }) "$k -> $($paths[$k])"
}

# Cursor process
$cursorProc = Get-Process cursor -ErrorAction SilentlyContinue
Add-R "Cursor" $(if ($cursorProc) { "RUNNING" } else { "STOPPED" }) $(if ($cursorProc) { "PID $($cursorProc.Id)" } else { "no cursor.exe" })

# Load env keys
$jcmRoot = $paths["JCM"]
$envFile = Join-Path $jcmRoot ".env"
$botEnv = Join-Path $jcmRoot "infra\bot-integration\bsv32-forward-bot.env"
$keys = @{}
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([A-Z_]+)=(.+)$') { $keys[$Matches[1]] = $Matches[1].Trim() }
    }
}
$fwdKey = ""; $wdKey = ""; $webhookSecret = ""
if (Test-Path $botEnv) {
    Get-Content $botEnv | ForEach-Object {
        if ($_ -match '^\s*FORWARD_BOT_API_KEY=(.+)$') { $fwdKey = $Matches[1].Trim() }
        if ($_ -match '^\s*WATCHDOG_API_KEY=(.+)$') { $wdKey = $Matches[1].Trim() }
        if ($_ -match '^\s*JCM_WEBHOOK_SECRET=(.+)$') { $webhookSecret = $Matches[1].Trim() }
    }
}

# Health checks
$checks = @(
    @{ Name = "JCM API"; Url = "http://127.0.0.1:8000/health" },
    @{ Name = "JCM Dashboard"; Url = "http://127.0.0.1:3000" },
    @{ Name = "MT5 API"; Url = "http://127.0.0.1:8765/health" },
    @{ Name = "Desk API"; Url = "http://127.0.0.1:8791/health" }
)
if ($fwdKey) { $checks += @{ Name = "Forward sidecar"; Url = "http://127.0.0.1:8083/health"; Headers = @{ Authorization = "Bearer $fwdKey" } } }
if ($wdKey) { $checks += @{ Name = "Watchdog sidecar"; Url = "http://127.0.0.1:8084/health"; Headers = @{ Authorization = "Bearer $wdKey" } } }

foreach ($c in $checks) {
    try {
        $params = @{ Uri = $c.Url; UseBasicParsing = $true; TimeoutSec = 8 }
        if ($c.Headers) { $params.Headers = $c.Headers }
        $r = Invoke-WebRequest @params
        Add-R "Health" "OK" "$($c.Name) $($r.StatusCode)"
    } catch {
        Add-R "Health" "FAIL" "$($c.Name) $($_.Exception.Message)"
    }
}

# API overview
try {
    $ov = Invoke-RestMethod "http://127.0.0.1:8000/dashboard/overview" -TimeoutSec 10
    Add-R "Dashboard" "INFO" "BSv32=$($ov.bsv32_status) MT5=$($ov.mt5_connected) alerts=$($ov.active_alerts_count) infra=$($ov.infra_health_score)"
} catch {
    Add-R "Dashboard" "FAIL" $_.Exception.Message
}

# Redis ping via API health already; direct test
try {
    $null = Invoke-RestMethod "http://127.0.0.1:8000/health"
    Add-R "Redis" "OK" "via API health"
} catch {
    Add-R "Redis" "FAIL" $_.Exception.Message
}

Write-Host ""
$Report | Format-Table -AutoSize
Write-Host "=== END AUDIT ===" -ForegroundColor Cyan
