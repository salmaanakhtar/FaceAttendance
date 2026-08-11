# AGENTS.md — FaceAttendance

FaceAttendance is a production-quality Android employee attendance system built
around facial check-in/check-out. Kiosk devices scan faces; the backend is the
system of record for raw scan events, derived attendance, corrections, and
audit.

This file is the entry point for any fresh agent. Read `docs/` before touching
code. Update docs when behavior changes materially.

## Repository layout

- `backend/` — Node.js + TypeScript + Fastify + PostgreSQL. REST API, attendance
  engine, migrations, unit tests.
- `app/` — Flutter Android client. Scanner-first kiosk app + in-app admin.
- `docs/` — architecture, setup, data model, biometrics, attendance rules,
  security, status, limitations, gauntlet findings.
- `scripts/` — machine-level dev helpers (db start/stop, devices, sync).

## System of record / rules of thumb

- Server time is authoritative for attendance timestamps. Devices send their
  own timestamps as metadata, never as truth.
- Raw scanner events (`scan_events`) are immutable and never edited.
  Corrections create new records + audit entries; they never mutate raw events.
- Biometric templates are encrypted at rest server-side and on-device. Raw face
  imagery is not stored; only enrollment quality metadata and templates.
- Duplicate attendance suppression is enforced server-side via idempotency
  keys + min-interval rules (see docs/attendance-rules.md).
- Dedupe/guard logic must be deterministic and unit tested. The attendance
  engine is a pure module — no I/O in core rules.

## Toolchain (this machine)

- Windows 11, PowerShell 5.1. Flutter 3.22.1 (stable, Dart 3.4.1),
  Node 24.14.0, npm 11.9.0, gh 2.87.3 (authed as salmaanakhtar).
- Android SDK at `$env:LOCALAPPDATA\Android\Sdk`. `adb` is NOT on PATH; use
  the full path or `scripts/devices.ps1`.
- Emulators (AVDs): `Kiosk_API_30_64`, `Medium_Tablet_API_30`.
- System services exist for Postgres (5432), MySQL (3306), MongoDB (27017) —
  do NOT touch them. Our project Postgres cluster runs on port **5434** with
  data in `backend/.pgdata` (see `scripts/db_start.ps1`).
- Project ports: API **4747**, Postgres **5434**. Check `Get-NetTCPConnection
  -State Listen` before starting anything; never kill unrelated processes.

## Commands

### Backend
- `cd backend; npm install`
- `../scripts/db_start.ps1` — start project Postgres on 5434 (data dir
  `backend/.pgdata`). Requires `initdb`/`pg_ctl` from a local Postgres 18
  install on PATH.
- `npm run db:migrate` — run migrations
- `npm run db:seed` — seed demo org, device, employees (passwords in
  backend/README.md)
- `npm run dev` — start API on 4747 (use `scripts/api_start.ps1` detached
  instead of foreground per global rules)
- `npm test` — vitest unit tests (attendance engine + services)
- `npm run typecheck`

### Flutter app
- `cd app; flutter pub get`
- `flutter run -d <device>` — see `scripts/devices.ps1` for device list
- `flutter test` — widget tests
- `flutter analyze` — static analysis

### Git
- Push meaningful progress frequently: `git add -A; git commit; git push`.
- GitHub is the source of truth; repo: `salmaanakhtar/FaceAttendance` (private).

## Background processes (global rule)

NEVER run servers in the foreground of an agent shell — the shell hangs.
Use the scripts in `scripts/` (Start-Process detached, logs to
`$env:TEMP\faceatt-*.log`). Stop only processes you started (matched by
command line). Helpers: `C:\Users\akhta\Documents\PowerShell\Start-Detached.ps1`.

## Current status

See `docs/status.md`. Update it on every meaningful change.

## Gauntlet

See `docs/gauntlet-findings.md` for per-cycle builder/critic findings and the
current largest gap. The loop: builder implements → critic runs the real
product (emulator + webcam, T3 vision agent for screens) → compare to quality
bar → send largest gap back to builder.
