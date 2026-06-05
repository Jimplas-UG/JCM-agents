$pattern = if ($args[0]) { $args[0] } else { "realistic-mt5-*" }
$Backend = "C:\opt\bilshenz\backend"
$files = Get-ChildItem $Backend -Recurse -Filter "*$pattern*output.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if (-not $files) { Write-Host "No report found for $pattern"; exit 1 }
$latest = $files[0]
Write-Host "FILE: $($latest.FullName)"
Get-Content $latest.FullName
