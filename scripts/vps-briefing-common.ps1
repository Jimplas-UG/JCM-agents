# Shared paths for briefing jobs (SYSTEM + Administrator).
$script:JcmBriefingRoot = "C:\jcm-project"
$script:JcmBriefingBackend = "$script:JcmBriefingRoot\backend"
$script:JcmBriefingPy = "$script:JcmBriefingBackend\.venv\Scripts\python.exe"
$script:JcmBriefingEnv = "$script:JcmBriefingRoot\.env"
$script:JcmBriefingLogDir = "C:\logs\jcm"

function Initialize-JcmBriefingRuntime {
    if (-not (Test-Path $script:JcmBriefingLogDir)) {
        New-Item -ItemType Directory -Path $script:JcmBriefingLogDir -Force | Out-Null
    }
    if (-not (Test-Path $script:JcmBriefingPy)) {
        throw "Python venv missing: $($script:JcmBriefingPy)"
    }
    if (-not (Test-Path $script:JcmBriefingEnv)) {
        throw ".env missing: $($script:JcmBriefingEnv)"
    }
    Copy-Item $script:JcmBriefingEnv (Join-Path $script:JcmBriefingBackend ".env") -Force
    Set-Location $script:JcmBriefingBackend
}

function Write-JcmBriefingLog($msg, $tag = "") {
    $prefix = if ($tag) { "[$tag] " } else { "" }
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $prefix$msg"
    Add-Content -Path (Join-Path $script:JcmBriefingLogDir "daily-briefing-telegram.log") -Value $line
    Write-Host $line
}
