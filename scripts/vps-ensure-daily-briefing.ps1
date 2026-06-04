# Alias: full permanent briefing pipeline (see vps-ensure-briefing-pipeline.ps1).
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $here "vps-ensure-briefing-pipeline.ps1")
