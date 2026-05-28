#Requires -Version 5.1
<#
.SYNOPSIS
  Set the BSv3.2 (Bilshenz) installation folder in .env.

.EXAMPLE
  .\scripts\set-bsv32-home.ps1 -Path "D:\Trading\BSv3.2"
  .\scripts\set-bsv32-home.ps1 -Path "C:\opt\bilshenz"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\jcm-env.ps1"
$Root = Get-JcmRoot -FromScript $PSScriptRoot

if (-not (Test-Path $Path)) {
    Write-Warning "Path does not exist yet: $Path"
}

try {
    $normalized = (Resolve-Path -LiteralPath $Path).Path
} catch {
    $normalized = [System.IO.Path]::GetFullPath($Path)
}

Set-EnvFileValue -Root $Root -Name "BSV32_HOME" -Value $normalized
[Environment]::SetEnvironmentVariable("BSV32_HOME", $normalized, "Process")

Write-Host "BSV32_HOME set to: $normalized" -ForegroundColor Green
Write-Host "Restart platform after changing API URLs: .\scripts\stop-platform.ps1; .\scripts\start-platform.ps1"
