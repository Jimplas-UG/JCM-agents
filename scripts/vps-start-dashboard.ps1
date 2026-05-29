$ErrorActionPreference = "Continue"
$Root = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Frontend = Join-Path $Root "frontend"
$Standalone = Join-Path $Frontend ".next\standalone"
$LogDir = Join-Path $Root "backend\logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Next standalone requires static assets beside server.js
$staticSrc = Join-Path $Frontend ".next\static"
$staticDst = Join-Path $Standalone ".next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst
}
$pubSrc = Join-Path $Frontend "public"
$pubDst = Join-Path $Standalone "public"
if (Test-Path $pubSrc) {
    Copy-Item -Recurse -Force $pubSrc $pubDst
}

$listen = Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
if ($listen) {
    Write-Host "Dashboard already on :3000"
    exit 0
}

$server = Join-Path $Standalone "server.js"
if (-not (Test-Path $server)) {
    Write-Host "Missing $server - run: cd frontend; npm run build"
    exit 1
}

$env:PORT = "3000"
$env:HOSTNAME = "0.0.0.0"
Start-Process -FilePath "node" -ArgumentList "server.js" -WorkingDirectory $Standalone `
    -RedirectStandardOutput (Join-Path $LogDir "frontend.log") `
    -RedirectStandardError (Join-Path $LogDir "frontend.err.log") `
    -WindowStyle Hidden
Start-Sleep -Seconds 8
try {
    $r = Invoke-WebRequest "http://127.0.0.1:3000" -UseBasicParsing -TimeoutSec 10
    Write-Host "Dashboard OK $($r.StatusCode)"
} catch {
    Write-Host "Dashboard FAIL - see frontend.err.log"
}
