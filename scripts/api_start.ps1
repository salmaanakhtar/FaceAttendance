# Start the API detached (global rule: never run servers in the agent shell).
. $PSScriptRoot\faceatt-common.ps1
$root = Split-Path $PSScriptRoot -Parent
$api = Join-Path $env:TEMP 'faceatt-api.log'

# Kill only stale instances of OUR api (npm start / tsx src/server.ts in this project).
Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -match 'faceattendance' -and $_.CommandLine -match 'server\.ts|faceatt-api' -and $_.Name -match 'node|cmd'
} | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

Start-Process -FilePath 'cmd.exe' -ArgumentList @('/c', "cd /d `"$root\backend`" && npm start > `"$api`" 2>&1") -WindowStyle Hidden
Start-Sleep -Seconds 2
if (Get-NetTCPConnection -State Listen -LocalPort 4747 -ErrorAction SilentlyContinue) {
  "API listening on 4747 (log: $api)"
} else {
  "API starting... check $api"
}
