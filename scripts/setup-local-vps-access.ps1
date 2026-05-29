# Setup local SSH access for Cursor Remote-SSH -> JCM VPS
# Run in PowerShell: .\scripts\setup-local-vps-access.ps1

param(
    [Parameter(Mandatory = $true)]
    [string]$VpsIp,

    [string]$SshUser = "root",
    [int]$SshPort = 22
)

$ErrorActionPreference = "Stop"
$sshDir = "$env:USERPROFILE\.ssh"
$keyPath = "$sshDir\jcm_vps"
$configPath = "$sshDir\config"

if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

if (-not (Test-Path $keyPath)) {
    Write-Host "Creating SSH key at $keyPath ..."
    ssh-keygen -t ed25519 -f $keyPath -N '""' -C "jcm-cursor-local"
}

$pubKey = Get-Content "$keyPath.pub" -Raw

$hostBlock = @"

# JCM VPS — added by setup-local-vps-access.ps1
Host jcm-vps
    HostName $VpsIp
    User $SshUser
    Port $SshPort
    IdentityFile $keyPath
    IdentitiesOnly yes
"@

if (Test-Path $configPath) {
    $existing = Get-Content $configPath -Raw
    if ($existing -notmatch "Host jcm-vps") {
        Add-Content -Path $configPath -Value $hostBlock
    } else {
        Write-Host "Host jcm-vps already in $configPath — edit IP/user manually if needed."
    }
} else {
    Set-Content -Path $configPath -Value $hostBlock.TrimStart()
}

# Restrict permissions on Windows (optional but good practice)
icacls $sshDir /inheritance:r /grant "${env:USERNAME}:(OI)(CI)F" 2>$null | Out-Null

Write-Host ""
Write-Host "=== LOCAL SETUP DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "1) Run this ONE command ON YOUR VPS (paste your public key):"
Write-Host ""
Write-Host "mkdir -p ~/.ssh && echo '$($pubKey.Trim())' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
Write-Host ""
Write-Host "2) Test from this PC:"
Write-Host "   ssh jcm-vps"
Write-Host ""
Write-Host "3) In Cursor: Install extension 'Remote - SSH'"
Write-Host "   Ctrl+Shift+P -> Remote-SSH: Connect to Host -> jcm-vps"
Write-Host "   Open folder: /opt/jcm"
Write-Host ""
