# FaceAttendance

Facial check-in/check-out attendance for real employees, built for Android
kiosk devices. Scanner-first Flutter client + Node/TypeScript/Fastify backend
with a deterministic attendance engine.

- **Scanner** — the app opens directly into face check-in powered by AWS
  Rekognition; worker-code punch remains the offline/fallback path.
- **Admin** — locked behind the top-right lock icon: employees, enrollment,
  attendance, corrections with full audit.
- **Backend** — server-side Rekognition matching, immutable scan events,
  derived sessions, audit trail, exports.
- **Web admin** — a React desktop browser dashboard in `web-admin/` for
  workers, attendance, leave, payroll, overtime and audit. It uses the same
  backend and does not change or bundle the Android kiosk app.

## Docs

- [Architecture](docs/architecture.md) · [Setup](docs/setup.md) ·
  [Data model](docs/data-model.md) · [Biometrics](docs/biometrics.md) ·
  [Rekognition](docs/rekognition.md) · [Attendance rules](docs/attendance-rules.md) ·
  [Overtime](docs/overtime.md) · [Security](docs/security.md) ·
  [Status](docs/status.md) · [Limitations](docs/limitations.md) ·
  [Gauntlet findings](docs/gauntlet-findings.md)

## Quick start

See [docs/setup.md](docs/setup.md). TL;DR:

```powershell
scripts\db_start.ps1
cd backend; npm install; npm run db:migrate; npm run db:seed
scripts\api_start.ps1
cd app; flutter pub get; flutter run -d <avd>
cd web-admin; npm install; npm run dev   # dashboard on http://127.0.0.1:4750
```

Set the AWS Rekognition variables in `backend/.env` before using face
check-in. See [`docs/rekognition.md`](docs/rekognition.md).
