#Requires -Version 5.1
<#
.SYNOPSIS
  Shared helpers to read JCM .env values (used by deploy and BSv3.2 integration scripts).
#>

function Get-JcmRoot {
    param([string]$FromScript = $PSScriptRoot)
    Split-Path -Parent (Split-Path -Parent $FromScript)
}

function Get-EnvFileValue {
    param(
        [string]$Root,
        [string]$Name,
        [string]$Default = ""
    )
    $path = Join-Path $Root ".env"
    if (-not (Test-Path $path)) { return $Default }
    foreach ($line in Get-Content $path) {
        if ($line -match "^\s*$([regex]::Escape($Name))=(.*)$") {
            $val = $Matches[1].Trim()
            if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Substring(1, $val.Length - 2) }
            if ($val.StartsWith("'") -and $val.EndsWith("'")) { $val = $val.Substring(1, $val.Length - 2) }
            return $val
        }
    }
    return $Default
}

function Set-EnvFileValue {
    param(
        [string]$Root,
        [string]$Name,
        [string]$Value
    )
    $path = Join-Path $Root ".env"
    if (-not (Test-Path $path)) {
        Copy-Item (Join-Path $Root ".env.example") $path
    }
    $lines = Get-Content $path
    $found = $false
    $newLines = foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Name))=") {
            $found = $true
            "$Name=$Value"
        } else { $line }
    }
    if (-not $found) { $newLines += "$Name=$Value" }
    $newLines | Set-Content $path -Encoding UTF8
}

function Get-Bsv32Home {
    <#
    .SYNOPSIS
      BSv3.2 / Bilshenz installation directory.
      Order: $env:BSV32_HOME, .env BSV32_HOME, default C:\opt\bilshenz
    #>
    param(
        [string]$Root = (Get-JcmRoot -FromScript $PSScriptRoot),
        [string]$Override = ""
    )
    if ($Override) {
        return $Override.Trim().TrimEnd('\')
    }
    if ($env:BSV32_HOME) {
        return $env:BSV32_HOME.Trim().TrimEnd('\')
    }
    $fromFile = Get-EnvFileValue -Root $Root -Name "BSV32_HOME" -Default ""
    if ($fromFile) {
        return $fromFile.Trim().TrimEnd('\')
    }
    return "C:\opt\bilshenz"
}
