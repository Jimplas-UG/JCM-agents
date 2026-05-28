#Requires -Version 5.1
<#
.SYNOPSIS
  Deploy JCM platform natively on Windows Server (no Linux Docker required).
  Uses local PostgreSQL + Redis already on this VPS.
#>
param(
    [switch]$SkipCheck,
    [switch]$Start
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "JCM Platform - Native Windows Deploy" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Error ".env created from example - set secrets and re-run."
}

function Set-EnvLine($name, $value) {
    $path = Join-Path $Root ".env"
    $lines = Get-Content $path
    $found = $false
    $newLines = foreach ($line in $lines) {
        if ($line -match "^\s*$name=") {
            $found = $true
            "$name=$value"
        } else { $line }
    }
    if (-not $found) { $newLines += "$name=$value" }
    $newLines | Set-Content $path -Encoding UTF8
}

# Native Windows networking
Set-EnvLine "POSTGRES_HOST" "localhost"
Set-EnvLine "REDIS_HOST" "localhost"
Set-EnvLine "APP_ENV" "production"
Set-EnvLine "METRICS_REQUIRE_AUTH" "false"

$publicUrl = "http://104.194.140.203:8000"
foreach ($line in Get-Content ".env") {
    if ($line -match '^\s*PLATFORM_PUBLIC_URL=(.+)$') {
        $publicUrl = $Matches[1].Trim()
        break
    }
}
$wsUrl = $publicUrl -replace '^http', 'ws'
Set-EnvLine "NEXT_PUBLIC_API_URL" $publicUrl
Set-EnvLine "NEXT_PUBLIC_WS_URL" "${wsUrl}/ws"
Set-EnvLine "PLATFORM_PUBLIC_URL" $publicUrl

$apiKey = (Get-Content ".env" | Where-Object { $_ -match '^\s*API_SECRET_KEY=' } | ForEach-Object { $_ -replace '^\s*API_SECRET_KEY=', '' })
if ($apiKey) { Set-EnvLine "NEXT_PUBLIC_API_KEY" $apiKey.Trim() }

# Bilshenz APIs on same host
Set-EnvLine "MT5_API_URL" "http://127.0.0.1:8765"
Set-EnvLine "DESK_API_URL" "http://127.0.0.1:8791"
Set-EnvLine "FORWARD_BOT_API_URL" "http://127.0.0.1:8083"
Set-EnvLine "WATCHDOG_API_URL" "http://127.0.0.1:8084"

if (-not $SkipCheck) {
    & "$Root\scripts\pre-deploy.ps1"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

# Backend dependencies
Write-Host "`nInstalling Python dependencies ..."
Set-Location "$Root\backend"
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
python -m pip install -r requirements.txt
if ($LASTEXITCODE -ne 0) { $ErrorActionPreference = $prevEap; Write-Error "pip install failed" }
python -m pip install -r requirements-dev.txt 2>&1 | Out-Null
$ErrorActionPreference = $prevEap

Write-Host "Initializing database (if needed) ..."
Set-Location $Root
python "$Root\scripts\init_db.py"
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Database init had issues - verify PostgreSQL credentials in .env"
}

# Frontend build
Write-Host "`nBuilding dashboard ..."
Set-Location "$Root\frontend"
if (-not (Test-Path "node_modules")) { npm install }
npm run build
Set-Location $Root

Write-Host "`nNative deployment artifacts ready." -ForegroundColor Green

if ($Start) {
    & "$Root\scripts\start-platform.ps1"
} else {
    Write-Host "Start services: .\scripts\start-platform.ps1" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  API:       $publicUrl"
Write-Host "  Dashboard: $($publicUrl -replace ':8000', ':3000')"
Write-Host "  Health:    $publicUrl/health"
