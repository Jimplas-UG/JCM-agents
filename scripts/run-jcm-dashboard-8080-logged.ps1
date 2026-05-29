$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Log = Join-Path $Root "backend\logs\dashboard-start.log"
$standalone = Join-Path $Root "frontend\.next\standalone\server.js"
"$(Get-Date -Format o) start dashboard-8080 standalone=$standalone exists=$(Test-Path $standalone)" | Out-File $Log -Append
try {
    & (Join-Path $Root "scripts\run-jcm-dashboard-8080.ps1") *>> $Log 2>&1
} catch {
    $_ | Out-File $Log -Append
}
