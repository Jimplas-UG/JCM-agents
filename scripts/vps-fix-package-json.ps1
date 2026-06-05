# Repair package.json and add institutional:readiness script without corrupting JSON.
$pkgPath = "C:\opt\bilshenz\backend\package.json"
$raw = [System.IO.File]::ReadAllText($pkgPath)
# Strip BOM if present
if ($raw.Length -gt 0 -and [int][char]$raw[0] -eq 0xFEFF) {
    $raw = $raw.Substring(1)
}
$j = $raw | ConvertFrom-Json
if (-not $j.scripts.'institutional:readiness') {
    $j.scripts | Add-Member -NotePropertyName 'institutional:readiness' -NotePropertyValue 'npx tsx scripts/run-institutional-readiness.ts' -Force
}
$out = $j | ConvertTo-Json -Depth 20 -Compress
[System.IO.File]::WriteAllText($pkgPath, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host "package.json repaired"
