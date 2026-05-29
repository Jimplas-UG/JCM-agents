# Monitor ports every 10s for 90s - detect what dies and when
$ErrorActionPreference = "Continue"
Write-Host "=== STABILITY MONITOR $(Get-Date -Format o) ==="
1..9 | ForEach-Object {
    $t = Get-Date -Format "HH:mm:ss"
    $s = (8765,8791,8000,3000,8083,8084 | ForEach-Object {
        $up = Get-NetTCPConnection -LocalPort $_ -State Listen -EA SilentlyContinue
        "$_$(if($up){'+'}else{'-'})"
    }) -join " "
    Write-Host "$t  $s"
    Start-Sleep -Seconds 10
}
Write-Host "=== END MONITOR ==="
