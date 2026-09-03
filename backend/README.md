# FaceAttendance backend

Node.js + TypeScript + Fastify + PostgreSQL (project-local cluster, port 5434).

## Commands

```powershell
npm install
../scripts/db_start.ps1      # start project Postgres on :5434
npm run db:migrate
npm run db:seed
npm run dev                  # API on :4747 (use ../scripts/api_start.ps1 detached)
npm test                     # vitest — attendance engine + services
npm run typecheck
```

## Demo credentials (dev seed only)

- Admin login: `admin` / `admin123` (POST /api/v1/admin/login)
- Device handshake: `kiosk-demo-001` (POST /api/v1/device/handshake with `{ deviceKey, name }`)

## API overview

| Method | Path | Auth | Purpose |
|---|---|---|---|
| POST | /api/v1/device/handshake | deviceKey | exchange provisioning key for device token |
| POST | /api/v1/scans | device | ingest scan event (idempotent, server time authoritative) |
| GET | /api/v1/device/templates | device | encrypted template bundle for kiosk sync |
| GET | /api/v1/device/config | device | org config + server clock + measured offset |
| POST | /api/v1/admin/login / refresh / logout | — | admin auth (sessions, revocable) |
| GET | /api/v1/admin/me | admin | current admin |
| GET/POST/PATCH | /api/v1/admin/employees[/:id] | admin | employee CRUD + search/filter |
| POST | /api/v1/admin/employees/:id/enroll | admin | submit fused embedding (encrypted at rest) |
| POST | /api/v1/admin/employees/:id/deactivate\|delete | admin | soft lifecycle, audited |
| GET | /api/v1/admin/attendance/now | admin | currently checked in |
| GET | /api/v1/admin/attendance | admin | sessions list w/ filters + pagination |
| GET | /api/v1/admin/attendance/employee/:id | admin | per-employee history + totals |
| GET | /api/v1/admin/attendance/stats | admin | aggregates: late/early/ot/missed/anomalies |
| GET | /api/v1/admin/attendance/absence | admin | absence + approved-leave totals by worker |
| GET/POST/PATCH | /api/v1/admin/leave[/:id] | admin | track and approve worker leave |
| POST | /api/v1/admin/corrections | admin | manual override (add/edit, audited) |
| GET | /api/v1/admin/corrections | admin | correction history |
| GET | /api/v1/admin/scan-events | admin | raw immutable events (transparency) |
| GET | /api/v1/admin/audit | admin | audit log |
| GET | /api/v1/admin/export?from&to | admin | CSV export of sessions |

## Layout

- `src/services/attendance/engine.ts` — PURE attendance engine (no I/O), fully unit tested
- `src/services/attendance/service.ts` — transactional persistence around the engine
- `src/routes/` — Fastify route groups with JSON Schema validation
- `db/migrations/` — SQL migrations; `db/migrate.ts` runner; `db/seed.ts` demo data
