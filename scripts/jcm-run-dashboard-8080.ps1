Set-Location "C:\jcm-project\frontend\.next\standalone"
$env:PORT = "8080"
$env:HOSTNAME = "0.0.0.0"
$staticSrc = "C:\jcm-project\frontend\.next\static"
$staticDst = "C:\jcm-project\frontend\.next\standalone\.next\static"
if (Test-Path $staticSrc) {
    New-Item -ItemType Directory -Force -Path (Split-Path $staticDst) | Out-Null
    Copy-Item -Recurse -Force $staticSrc $staticDst -EA SilentlyContinue
}
& "C:\Program Files\nodejs\node.exe" server.js
