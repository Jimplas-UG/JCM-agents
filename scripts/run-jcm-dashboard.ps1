$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$standalone = Join-Path $Root "frontend\.next\standalone"
$staticSrc = Join-Path $Root "frontend\.next\static"
$staticDst = Join-Path $standalone ".next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}
$pubSrc = Join-Path $Root "frontend\public"
if (Test-Path $pubSrc) { Copy-Item -Recurse -Force $pubSrc (Join-Path $standalone "public") -EA SilentlyContinue }
$env:PORT = "3000"
$env:HOSTNAME = "0.0.0.0"
$node = "C:\Program Files\nodejs\node.exe"
if (-not (Test-Path $node)) { $node = (Get-Command node.exe -EA SilentlyContinue).Source }
Set-Location $standalone
& $node server.js
