$infra = "C:\Users\Administrator\Documents\JCM agents\JCM-agents\backend\infra"
New-Item -ItemType Directory -Force -Path $infra | Out-Null
Move-Item -Force "C:\Users\Administrator\subscriptions.json" (Join-Path $infra "subscriptions.json")
Write-Host "OK: $(Join-Path $infra 'subscriptions.json')"
