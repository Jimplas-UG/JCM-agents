# One-shot WordPress plugin upload + activate (cookie-aware)
$ErrorActionPreference = "Stop"
$Site = "https://www.jimplascapital.com"
$Zip = Join-Path $PSScriptRoot "..\wordpress\jcm-ceo-copilot.zip"
$Cookie = Join-Path $PSScriptRoot "..\wordpress\wp-session.txt"
$user = $env:WP_USER
$pass = $env:WP_PASS
if (-not $user -or -not $pass) {
    Write-Error "Set WP_USER and WP_PASS environment variables before running."
}

Remove-Item $Cookie -Force -ErrorAction SilentlyContinue
curl.exe -s -c $Cookie -b $Cookie --max-time 30 "$Site/wp-login.php" -o NUL | Out-Null
curl.exe -s -c $Cookie -b $Cookie -L --max-time 60 `
  -d "log=$user&pwd=$pass&wp-submit=Log+In&redirect_to=$Site/wp-admin/plugins.php&testcookie=1" `
  "$Site/wp-login.php" -o NUL | Out-Null

$uploadPage = (curl.exe -s -b $Cookie --max-time 60 "$Site/wp-admin/plugin-install.php?tab=upload" | Out-String)
if ($uploadPage -notmatch 'name="_wpnonce"\s+value="([^"]+)"') { throw "No upload nonce" }
$nonce = $Matches[1]

curl.exe -s -b $Cookie -L --max-time 120 `
  -F "_wpnonce=$nonce" `
  -F "_wp_http_referer=/wp-admin/plugin-install.php?tab=upload" `
  -F "pluginzip=@$Zip" `
  -F "install-plugin-submit=Install Now" `
  "$Site/wp-admin/update.php?action=upload-plugin" `
  -o (Join-Path $PSScriptRoot "..\wordpress\wp-upload-final.html") | Out-Null

$plugins = (curl.exe -s -b $Cookie --max-time 60 "$Site/wp-admin/plugins.php" | Out-String)
if ($plugins -match 'data-plugin="(jcm-private-copilot/jcm-private-copilot\.php)"') {
    $pluginPath = $Matches[1]
} else {
    throw "Plugin not found after upload"
}

if ($plugins -match "activate&amp;plugin=jcm-private-copilot%2Fjcm-private-copilot\.php[^&]*&amp;_wpnonce=([a-f0-9]+)") {
    $actNonce = $Matches[1]
    curl.exe -s -b $Cookie -L --max-time 60 `
      "$Site/wp-admin/plugins.php?action=activate&plugin=jcm-private-copilot/jcm-private-copilot.php&_wpnonce=$actNonce" `
      -o (Join-Path $PSScriptRoot "..\wordpress\wp-activate-final.html") | Out-Null
}

$verify = (curl.exe -s -b $Cookie --max-time 60 "$Site/wp-admin/plugins.php" | Out-String)
if ($verify -match 'deactivate-jcm-private-copilot|Deactivate JCM CEO Copilot') {
    Write-Host "SUCCESS: CEO Copilot plugin is active on jimplascapital.com"
} else {
    Write-Host "Upload done - activate manually in Plugins if needed."
}

$home = (curl.exe -s -b $Cookie --max-time 60 "$Site/" | Out-String)
if ($home -match 'jcm-ceo-copilot-launcher') {
    Write-Host "SUCCESS: Gold CEO Copilot button visible on website (logged in as admin)."
} else {
    Write-Host "Check website while logged in to wp-admin for the gold CEO Copilot button."
}
