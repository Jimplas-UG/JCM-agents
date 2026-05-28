# JCM sidecars: forward-bot + watchdog health on 8083/8084 (real MT5/desk on 8765/8791)
$ErrorActionPreference = "Continue"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvPython = Join-Path $here "..\..\backend\.venv\Scripts\python.exe"
$stub = Join-Path $here "stub_execution_layer.py"

if (-not (Test-Path $venvPython)) {
    Write-Error "Backend venv not found. Run: cd backend; python -m venv .venv; pip install -r requirements.txt"
}

# Install stub deps if needed
& $venvPython -m pip install python-dotenv psutil -q 2>$null

$services = @(
    @{ Name = "forward"; Port = 8083 },
    @{ Name = "watchdog"; Port = 8084 }
)

foreach ($svc in $services) {
    $existing = Get-NetTCPConnection -LocalPort $svc.Port -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Port $($svc.Port) already in use - skipping $($svc.Name)"
        continue
    }
    Start-Process -FilePath $venvPython -ArgumentList $stub, $svc.Name `
        -WorkingDirectory $here -WindowStyle Hidden
    Write-Host "Started $($svc.Name) stub on port $($svc.Port)"
}

Start-Sleep -Seconds 3

# Load API keys from integration env
$envFile = Join-Path $here "bsv32-forward-bot.env"
$keys = @{ 8083 = ""; 8084 = "" }
Get-Content $envFile | ForEach-Object {
    if ($_ -match '^\s*FORWARD_BOT_API_KEY=(.+)$') { $keys[8083] = $Matches[1].Trim() }
    if ($_ -match '^\s*WATCHDOG_API_KEY=(.+)$') { $keys[8084] = $Matches[1].Trim() }
}

Write-Host "`nHealth checks (JCM sidecars):"
foreach ($port in 8083, 8084) {
  try {
    $h = @{ Authorization = "Bearer $($keys[$port])" }
    $r = Invoke-WebRequest "http://127.0.0.1:$port/health" -Headers $h -UseBasicParsing -TimeoutSec 5
    Write-Host "  :$port -> $($r.StatusCode)"
  } catch {
    Write-Host "  :$port -> FAIL"
  }
}
