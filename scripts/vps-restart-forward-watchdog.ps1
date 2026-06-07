# Dedupe and restart forward + watchdog workers (tsx spawns parent cli + child loader — count child only)
$ErrorActionPreference = "Continue"
$tsxLeaf = "tsx\\dist\\cli\\.mjs"

function Get-Workers([string]$pattern) {
    @(Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match $pattern -and $_.CommandLine -notmatch $tsxLeaf
    })
}

Get-CimInstance Win32_Process -EA SilentlyContinue | Where-Object {
    $_.Name -eq 'node.exe' -and ($_.CommandLine -match 'run-forward-demo-30d|watchdog\.ts')
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
Start-Sleep 5

Write-Host "Starting forward bot..."
& "C:\opt\bilshenz\deploy\windows\run-forward-bot.ps1" -AppDir "C:\opt\bilshenz"
Start-Sleep 10

Write-Host "Starting watchdog..."
& "C:\opt\bilshenz\deploy\windows\run-watchdog.ps1" -AppDir "C:\opt\bilshenz"
Start-Sleep 8

$fwd = Get-Workers 'run-forward-demo-30d'
$wd = Get-Workers 'watchdog\.ts|watchdog\.vps\.ts'
Write-Host "Forward: $($fwd.Count) Watchdog: $($wd.Count)"
if ($fwd.Count -gt 0) { Write-Host "  forward PID $($fwd[0].ProcessId)" }
if ($wd.Count -gt 0) { Write-Host "  watchdog PID $($wd[0].ProcessId)" }
