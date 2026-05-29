$Jcm = "C:\Users\Administrator\Documents\JCM agents\JCM-agents"
$Admin = "C:\Users\Administrator"
Copy-Item "$Admin\vps-install-system-tasks.ps1" "$Jcm\scripts\" -Force
Copy-Item "$Admin\run-jcm-dashboard-8080.ps1" "$Jcm\scripts\" -Force
Copy-Item "$Admin\run-jcm-dashboard-8080-logged.ps1" "$Jcm\scripts\" -Force -EA SilentlyContinue
Copy-Item "$Admin\run-jcm-sidecar-fwd.ps1" "$Jcm\scripts\" -Force -EA SilentlyContinue
Copy-Item "$Admin\run-jcm-sidecar-wd.ps1" "$Jcm\scripts\" -Force -EA SilentlyContinue
Copy-Item "$Admin\watchdog.vps.ts" "$Jcm\watchdog.vps.ts" -Force
& "$Admin\vps-align-bilshenz-jcm.ps1"
