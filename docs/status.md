# Status

_Last update: 2026-08-12 — PROJECT COMPLETE (v1.0.0)._

## Deployed (production)

- **Backend**: https://faceattendance-api.salmaan.dev (containerized on
  VPS 169.58.162.229 via hermes platform, traefik TLS).
- **Database**: postgres:16 container `hermes-db-faceattendance`.
- **Org**: Yabil — timezone `Africa/Johannesburg` (business timezone;
  system clocks untouched; the app displays org-local time everywhere).
- **Device key**: `device@yabil` (kiosk provisioning).
- **Admin**: `admin` / `admin123` (role owner).
- **Employees**: none seeded — enrollment happens in-app (by design).

## App (final APK)

- `app/releases/FaceAttendance-v1.0.0-lan.apk` + GitHub release v1.0.0.
- Points at the VPS by default. Displays South Africa time via the org
  timezone (timezone package; local location = org tz on every launch).
- Scanner-first kiosk: on-device MobileFaceNet recognition, NV21 pipeline,
  presence lockout (one scan per presence), offline queue, auto-update
  (GitHub releases via backend proxy; needs `gh` authed in the API
  container to be active), admin console with enrollment, attendance,
  corrections + audit, CSV export.

## Local machine (this PC)

- Project Postgres (:5434) stopped, API (:4747) stopped, firewall rule
  removed, UDP dynamic port range restored. Nothing from this project is
  running locally anymore.
- `scripts/db_start.ps1` / `api_start.ps1` can bring it back for dev if
  ever needed (device key `kiosk-demo-001`, admin/admin123 — dev only).

## History highlights

- v0.1.x–v0.2.x: built scanner pipeline; fixed in order — bgra8888→NV21
  (ML Kit only accepts NV21/YV12/JPEG), single-plane NV21 delivery (Nothing
  3a), 90/270 rotation mapping, AES key length bug, liveness clamp + 429
  handling + presence lockout, silent auto-update.
- v0.3.0: VPS deployment (API base, auto re-handshake, Yabil rename).
- v1.0.0: clean VPS bootstrap, SA timezone on the frontend, project end.
