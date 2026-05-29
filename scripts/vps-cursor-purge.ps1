Get-Process | Where-Object { $_.ProcessName -match 'cursor|Cursor' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 3
$roam = "$env:USERPROFILE\AppData\Roaming\Cursor"
if (Test-Path $roam) {
    Get-ChildItem $roam -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item $roam -Force -Recurse -ErrorAction SilentlyContinue
}
Write-Host "Roaming Cursor: $(if (Test-Path $roam) { 'STILL EXISTS' } else { 'REMOVED' })"
