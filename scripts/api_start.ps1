# Start the API detached (global rule: never run servers in the agent shell).
. $PSScriptRoot\faceatt-common.ps1
$root = Split-Path $PSScriptRoot -Parent
$api = Join-Path $env:TEMP 'faceatt-api.log'
Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "cd /d `"$root\backend`" && npm run dev > `"$api`" 2>&1") -WindowStyle Hidden
Start-Sleep -Seconds 2
if (Get-NetTCPConnection -State Listen -LocalPort 4747 -ErrorAction SilentlyContinue) {
  "API listening on 4747 (log: $api)"
} else {
  "API starting... check $api"
}
