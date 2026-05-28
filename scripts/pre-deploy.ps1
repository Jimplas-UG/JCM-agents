#Requires -Version 5.1
<#
.SYNOPSIS
  Validate .env and prerequisites before deployment.
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$errors = @()

if (-not (Test-Path ".env")) {
    $errors += ".env missing - copy .env.example to .env and configure secrets"
} else {
    $envContent = Get-Content ".env" -Raw
    $required = @(
        "API_SECRET_KEY",
        "POSTGRES_PASSWORD",
        "EVENT_WEBHOOK_SECRET"
    )
    foreach ($key in $required) {
        if ($envContent -notmatch "$key=.+") {
            $errors += "$key is not set in .env"
        }
    }
    if ($envContent -match 'API_SECRET_KEY=change-me') {
        $errors += "API_SECRET_KEY is still the default placeholder"
    }
    if ($envContent -match 'POSTGRES_PASSWORD=changeme') {
        $errors += "POSTGRES_PASSWORD is still the default placeholder"
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    $errors += "Docker is not installed"
}

try {
    docker info 2>$null | Out-Null
} catch {
    $errors += "Docker daemon is not running"
}

if ($errors.Count -gt 0) {
    Write-Host "Pre-deploy FAILED:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Pre-deploy checks passed." -ForegroundColor Green
& python "$Root\scripts\security_check.py"
exit $LASTEXITCODE
