# Live factual test - run ON VPS, prints pass/fail with HTTP codes
$ErrorActionPreference = "Continue"
$ApiKey = "MlxG1e0W5D2fTQsAJEwdCmyFKYVrOb3qz4nphk7HR98ZaUvo"
$FwdKey = "jcm_s930px6rvhanj7kt5qi8fy41ocdu"
$WdKey = "jcm_caxs285n7flj0t4muord1z63hgbi"
$PublicIp = "104.194.140.203"

Write-Host "=== LIVE TEST $(Get-Date -Format o) ==="

Write-Host "`n[PORTS]"
foreach ($p in 8765,8791,8000,8080,3000,8083,8084,5432,6379) {
    $l = Get-NetTCPConnection -LocalPort $p -State Listen -EA SilentlyContinue | Select-Object -First 1
    Write-Host "  :$p $(if ($l) { "LISTEN pid=$($l.OwningProcess)" } else { "CLOSED" })"
}

Write-Host "`n[LOCALHOST HTTP]"
$tests = @(
    @{N="MT5 /health"; U="http://127.0.0.1:8765/health"},
    @{N="MT5 /api/status"; U="http://127.0.0.1:8765/api/status"},
    @{N="Desk /health"; U="http://127.0.0.1:8791/health"},
    @{N="JCM /health"; U="http://127.0.0.1:8000/health"},
    @{N="JCM /"; U="http://127.0.0.1:8000/"},
    @{N="Dashboard :8080"; U="http://127.0.0.1:8080/"},
    @{N="Dashboard :3000"; U="http://127.0.0.1:3000/"},
    @{N="Forward sidecar"; U="http://127.0.0.1:8083/health"; H=@{Authorization="Bearer $FwdKey"}},
    @{N="Watchdog sidecar"; U="http://127.0.0.1:8084/health"; H=@{Authorization="Bearer $WdKey"}}
)
foreach ($t in $tests) {
    try {
        $params = @{Uri=$t.U; UseBasicParsing=$true; TimeoutSec=10}
        if ($t.H) { $params.Headers = $t.H }
        $r = Invoke-WebRequest @params
        Write-Host "  PASS $($t.N) -> $($r.StatusCode)"
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "NO_CONN" }
        Write-Host "  FAIL $($t.N) -> $code"
    }
}

Write-Host "`n[PUBLIC IP HTTP from VPS]"
foreach ($t in @(
    @{N="Dashboard :8080 public"; U="http://${PublicIp}:8080/"},
    @{N="Dashboard :3000 public"; U="http://${PublicIp}:3000/"},
    @{N="API public"; U="http://${PublicIp}:8000/health"}
)) {
    try {
        $r = Invoke-WebRequest -Uri $t.U -UseBasicParsing -TimeoutSec 10
        Write-Host "  PASS $($t.N) -> $($r.StatusCode)"
    } catch {
        $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "NO_CONN" }
        Write-Host "  FAIL $($t.N) -> $code"
    }
}

Write-Host "`n[PROCESSES]"
$term = Get-Process terminal64 -EA SilentlyContinue
Write-Host "  MT5 terminal: $(if ($term) { "RUNNING pid=$($term.Id)" } else { "NOT RUNNING" })"
$fwd = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.Name -eq 'node.exe' -and $_.CommandLine -match 'run-forward-demo-30d' }
Write-Host "  Forward bot node: $(if ($fwd) { "RUNNING pid=$($fwd.ProcessId)" } else { "NOT RUNNING" })"
$mt5py = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'main\.py' -and $_.CommandLine -match 'mt5_trading_system|8765' }
if (-not $mt5py) {
    $mt5py = Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object { $_.CommandLine -match 'main\.py' }
}
Write-Host "  MT5 API python: $(if ($mt5py) { "RUNNING" } else { "NOT RUNNING" })"

Write-Host "`n[DASHBOARD LOGS]"
$feErr = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\logs\frontend.err.log"
$feOut = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\logs\frontend.log"
if (Test-Path $feErr) {
    Write-Host "  frontend.err.log (last 5):"
    Get-Content $feErr -Tail 5 | ForEach-Object { Write-Host "    $_" }
} else { Write-Host "  frontend.err.log: MISSING" }
if (Test-Path $feOut) {
    $fi = Get-Item $feOut
    Write-Host "  frontend.log size=$($fi.Length) modified=$($fi.LastWriteTime)"
}

Write-Host "`n[FORWARD BOT LOG tail]"
Get-Content "C:\logs\tradingbot\forward-bot.err.log" -Tail 4 -EA SilentlyContinue | ForEach-Object { Write-Host "  $_" }

Write-Host "`n=== END TEST ==="
