# Machine-level dev helpers for FaceAttendance.
# Ports: API 4747, Postgres 5434 (project-local cluster, never the system PG).

$ErrorActionPreference = 'Stop'

function Get-PGConfig {
  $pgBin = 'C:\Program Files\PostgreSQL\18\bin'
  if (-not (Test-Path "$pgBin\pg_ctl.exe")) {
    $c = Get-Command pg_ctl -ErrorAction SilentlyContinue
    if (-not $c) { throw 'PostgreSQL 18 binaries not found. Install or adjust Get-PGConfig.' }
    $pgBin = Split-Path $c.Source
  }
  return $pgBin
}

function Start-FaceAttDb {
  $root = Split-Path $PSScriptRoot -Parent
  $pgBin = Get-PGConfig
  $data = Join-Path $root 'backend\.pgdata'
  $log = Join-Path $env:TEMP 'faceatt-pg.log'
  $initLog = Join-Path $env:TEMP 'faceatt-pg-init.log'
  # Rule: never let a spawned process inherit our stdout/stderr pipes — the
  # caller would block until EOF. Everything is redirected to log files and
  # launched detached.
  if (-not (Test-Path "$data\PG_VERSION")) {
    Write-Host 'Initializing project Postgres cluster (port 5434)...'
    Start-Process -FilePath "$pgBin\initdb.exe" -ArgumentList @('-D', $data, '-U', 'postgres', '-A', 'trust', '-E', 'UTF8') `
      -WindowStyle Hidden -Wait -RedirectStandardOutput $initLog -RedirectStandardError "$initLog.err"
    Add-Content "$data\postgresql.conf" "`nport = 5434`nlisten_addresses = '127.0.0.1'`nunix_socket_directories = ''"
  }
  $running = Get-NetTCPConnection -State Listen -LocalPort 5434 -ErrorAction SilentlyContinue
  if (-not $running) {
    Start-Process -FilePath "$pgBin\pg_ctl.exe" -ArgumentList @('-D', $data, '-l', $log, 'start', '-w') `
      -WindowStyle Hidden -Wait -RedirectStandardOutput "$log.ctl" -RedirectStandardError "$log.ctl.err"
  }
  Start-Sleep -Seconds 2
  $conn = Get-NetTCPConnection -State Listen -LocalPort 5434 -ErrorAction SilentlyContinue
  if ($conn) { "Project Postgres listening on 5434 (log: $log)" } else { "WARN: 5434 not listening yet; check $log" }
}

function Stop-FaceAttDb {
  $root = Split-Path $PSScriptRoot -Parent
  $pgBin = Get-PGConfig
  $data = Join-Path $root 'backend\.pgdata'
  if (Test-Path "$data\postmaster.pid") {
    Start-Process -FilePath "$pgBin\pg_ctl.exe" -ArgumentList @('-D', $data, 'stop', '-m', 'fast') `
      -WindowStyle Hidden -Wait -RedirectStandardOutput "$env:TEMP\faceatt-pg-stop.log" -RedirectStandardError "$env:TEMP\faceatt-pg-stop.log.err"
    "Project Postgres stopped."
  } else { 'Project Postgres not running.' }
}
