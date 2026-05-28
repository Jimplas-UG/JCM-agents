#Requires -Version 5.1
<#
.SYNOPSIS
  Build and deploy the JCM supervisory platform with Docker Compose.
#>
param(
    [switch]$Build,
    [switch]$SkipCheck,
    [string]$PublicUrl = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host "JCM Platform - Deploy" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed or not in PATH."
}

$compose = "docker compose"
try {
    & docker compose version 2>$null | Out-Null
} catch {
    $compose = "docker-compose"
}

# Ensure .env exists
if (-not (Test-Path ".env")) {
    Write-Host "Creating .env from .env.example ..."
    Copy-Item ".env.example" ".env"
    Write-Host "Edit .env with your secrets, then re-run deploy." -ForegroundColor Yellow
    exit 1
}

# Load PLATFORM_PUBLIC_URL from .env if not passed
if (-not $PublicUrl) {
    foreach ($line in Get-Content ".env") {
        if ($line -match '^\s*PLATFORM_PUBLIC_URL=(.+)$') {
            $PublicUrl = $Matches[1].Trim()
            break
        }
    }
}
if (-not $PublicUrl) {
    $PublicUrl = "http://localhost:8000"
}

Write-Host "Public API URL: $PublicUrl"

# Patch .env for Docker networking (idempotent)
function Set-EnvLine($name, $value) {
    $path = Join-Path $Root ".env"
    $lines = Get-Content $path -ErrorAction SilentlyContinue
    $found = $false
    $newLines = foreach ($line in $lines) {
        if ($line -match "^\s*$name=") {
            $found = $true
            "$name=$value"
        } else {
            $line
        }
    }
    if (-not $found) {
        $newLines += "$name=$value"
    }
    $newLines | Set-Content $path -Encoding UTF8
}

$hostIp = if ($PublicUrl -match '^https?://([^:/]+)') { $Matches[1] } else { "localhost" }
$wsUrl = $PublicUrl -replace '^http', 'ws'

Set-EnvLine "POSTGRES_HOST" "postgres"
Set-EnvLine "REDIS_HOST" "redis"
Set-EnvLine "NEXT_PUBLIC_API_URL" $PublicUrl
Set-EnvLine "NEXT_PUBLIC_WS_URL" "${wsUrl}/ws"
Set-EnvLine "APP_ENV" "production"
Set-EnvLine "METRICS_REQUIRE_AUTH" "false"

# Dashboard API key must match backend secret for POST actions
$apiKey = (Get-Content ".env" | Where-Object { $_ -match '^\s*API_SECRET_KEY=' } | ForEach-Object { $_ -replace '^\s*API_SECRET_KEY=', '' })
if ($apiKey) {
    Set-EnvLine "NEXT_PUBLIC_API_KEY" $apiKey.Trim()
}

# Bilshenz stack on host - reachable from containers via host.docker.internal
if ($hostIp -match '^\d+\.\d+\.\d+\.\d+$' -or $hostIp -eq 'localhost') {
    Set-EnvLine "MT5_API_URL" "http://host.docker.internal:8765"
    Set-EnvLine "DESK_API_URL" "http://host.docker.internal:8791"
    Set-EnvLine "FORWARD_BOT_API_URL" "http://host.docker.internal:8083"
    Set-EnvLine "WATCHDOG_API_URL" "http://host.docker.internal:8084"
}

if (-not $SkipCheck) {
    Write-Host "`nPre-deploy checks ..."
    & python "$Root\scripts\security_check.py"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Security check reported issues - review .env before production." -ForegroundColor Yellow
    }
}

$buildArgs = @()
if ($Build) { $buildArgs += "--build" }

$upCmd = "$compose up -d $($buildArgs -join ' ')"
Write-Host ""
Write-Host "Starting stack: $upCmd"
Invoke-Expression $upCmd

Write-Host "`nWaiting for API health ..."
$max = 30
$ok = $false
for ($i = 1; $i -le $max; $i++) {
    Start-Sleep -Seconds 5
    try {
        $r = Invoke-RestMethod -Uri "$PublicUrl/health" -TimeoutSec 5
        if ($r.status -in @("healthy", "degraded")) {
            $ok = $true
            break
        }
    } catch { }
    Write-Host "  attempt $i/$max ..."
}

$dashUrl = $PublicUrl -replace ':8000', ':3000'
if ($PublicUrl -notmatch ':8000') { $dashUrl = "http://${hostIp}:3000" }

Write-Host "`n========================================" -ForegroundColor Green
if ($ok) {
    Write-Host "Deployment ready." -ForegroundColor Green
} else {
    Write-Host "Stack started - API health not confirmed yet." -ForegroundColor Yellow
    Write-Host "Check: $compose logs api" -ForegroundColor Yellow
}
Write-Host "  API:        $PublicUrl"
Write-Host "  Dashboard:  $dashUrl"
Write-Host "  Health:     $PublicUrl/health"
Write-Host "  Webhook:    $PublicUrl/ingest/event"
Write-Host "  Prometheus: http://127.0.0.1:9090 (localhost only)"
Write-Host "========================================" -ForegroundColor Green
