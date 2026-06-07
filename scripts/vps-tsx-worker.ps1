# tsx spawns parent (cli.mjs) + child (loader.mjs) — count leaf processes only.
function Get-TsxWorkerLeaves([string]$ScriptPattern) {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match "loader\.mjs.*$ScriptPattern"
    })
}

function Test-TsxWorkerRunning([string]$ScriptPattern) {
    return (Get-TsxWorkerLeaves $ScriptPattern).Count -ge 1
}

function Stop-TsxWorkerDuplicates([string]$ScriptPattern) {
    $leaves = Get-TsxWorkerLeaves $ScriptPattern
    if ($leaves.Count -le 1) { return $leaves }
    $keep = $leaves[-1].ProcessId
    foreach ($p in $leaves) {
        if ($p.ProcessId -ne $keep) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    return @(Get-TsxWorkerLeaves $ScriptPattern)
}

function Stop-TsxWorkerAll([string]$ScriptPattern) {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match $ScriptPattern
    } | ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Get-TsxWorkerNodeCount([string]$ScriptPattern) {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -eq 'node.exe' -and $_.CommandLine -match $ScriptPattern
    }).Count
}
