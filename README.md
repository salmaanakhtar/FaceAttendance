# FaceAttendance

Facial check-in/check-out attendance for real employees, built for Android
kiosk devices. Scanner-first Flutter client + Node/TypeScript/Fastify backend
with a deterministic attendance engine.

- **Scanner** — the app opens directly into face recognition; check in/out in
  under a second. Works offline, syncs when connectivity returns.
- **Admin** — locked behind the top-right lock icon: employees, enrollment,
  attendance, corrections with full audit.
- **Backend** — immutable scan events, derived sessions, audit trail, exports.

## Docs

- [Architecture](docs/architecture.md) · [Setup](docs/setup.md) ·
  [Data model](docs/data-model.md) · [Biometrics](docs/biometrics.md) ·
  [Attendance rules](docs/attendance-rules.md) · [Security](docs/security.md) ·
  [Status](docs/status.md) · [Limitations](docs/limitations.md) ·
  [Gauntlet findings](docs/gauntlet-findings.md)

## Quick start

See [docs/setup.md](docs/setup.md). TL;DR:

```powershell
scripts\db_start.ps1
cd backend; npm install; npm run db:migrate; npm run db:seed
scripts\api_start.ps1
cd app; flutter pub get; flutter run -d <avd>
```
