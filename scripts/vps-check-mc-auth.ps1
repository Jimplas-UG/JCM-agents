$paths = @(
    "C:\Users\Administrator\Documents\JCM agents\JCM-agents\.env",
    "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\.env",
    "C:\jcm-project\.env"
)
foreach ($p in $paths) {
    if (-not (Test-Path $p)) { Write-Host "$p : missing"; continue }
    $user = $false; $pass = $false; $req = $null
    Get-Content $p | ForEach-Object {
        if ($_ -match '^\s*MISSION_CONTROL_USER=(.+)$' -and $Matches[1].Trim()) { $user = $true }
        if ($_ -match '^\s*MISSION_CONTROL_PASSWORD=(.+)$' -and $Matches[1].Trim()) { $pass = $true }
        if ($_ -match '^\s*MISSION_CONTROL_REQUIRE_AUTH=(.+)$') { $req = $Matches[1].Trim() }
    }
    Write-Host "$p : USER=$user PASS=$pass REQUIRE_AUTH=$req"
}
