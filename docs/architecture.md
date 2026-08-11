# Architecture

## System overview

```
┌─────────────────────────────┐        HTTPS        ┌──────────────────────────┐
│  Android kiosk (Flutter)    │ ───────────────────►│  Backend (Fastify+TS)    │
│  Scanner-first kiosk mode   │  device auth + sync │  REST API on :4747       │
│  In-app admin (locked)      │ ◄───────────────────│  Attendance engine       │
│  On-device recognition      │  templates, config  │  PostgreSQL on :5434     │
└─────────────────────────────┘                     └──────────────────────────┘
```

## Design principles

1. **Scanner-first.** The app opens into the face scanner; every other surface
   is behind admin authentication. No menus between employee and scanning.
2. **Server time is authoritative.** Device timestamps are stored as metadata
   (`device_time`), never used as attendance truth. Clock drift is measured per
   device and accounted for.
3. **Raw events are immutable.** `scan_events` are append-only. Corrections
   never mutate them — they create corrected attendance records plus an audit
   trail.
4. **On-device recognition, server-synced templates.** Face embeddings
   (MobileFaceNet, 128-d) are computed on-device with TFLite. Matching happens
   locally so the kiosk keeps working offline. Templates are encrypted at rest
   server-side (AES-256-GCM) and on-device; raw face images are never stored.
5. **Deterministic attendance.** The attendance engine is a pure module
   (no I/O). Given raw events + policy, it produces sessions; output is a pure
   function of input, so it is unit-testable and reproducible.

## Backend modules

- `src/server.ts` — entrypoint, plugin wiring
- `src/routes/` — Fastify route groups (auth, employees, enrollment, scans,
  attendance, corrections, devices, audit, export)
- `src/services/` — attendance engine, enrollment quality, sync/dedupe,
  templates
- `src/lib/` — clock, ids, crypto, config
- `db/migrations/` — SQL migrations (node-pg-migrate)

## Client modules

- `lib/main.dart` — bootstrap, kiosk state
- `lib/scanner/` — camera pipeline, detection, recognition, scan state machine
- `lib/attendance/` — offline queue, sync client, event model
- `lib/admin/` — admin sign-in, dashboard, employee management, enrollment,
  history, corrections
- `lib/device/` — provisioning, kiosk lock, connectivity, feedback (audio/haptic)

## Key decisions (and why)

- **Flutter over native:** single codebase across phones/tablets/kiosks,
  strong camera + ML ecosystem, fast iteration.
- **MobileFaceNet + TFLite over server-side recognition:** offline operation is
  a hard requirement; embeddings are small (128 floats) and cheap to match.
- **PostgreSQL over SQLite:** concurrent kiosks, transaction-heavy corrections,
  realistic production target. Project-local cluster on :5434 so we never touch
  the machine's system Postgres.
- **Fastify over Express:** typed, fast, first-class TS support, built-in
  schema validation (JSON Schema).
- **Manual overrides create records, never edit them:** auditability is a core
  requirement; see docs/security.md.
