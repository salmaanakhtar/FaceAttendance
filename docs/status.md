# Status

_Updated per meaningful change. Last update: 2026-08-11 (Phase 1 complete)._

## What works

- **Backend (Phase 1) complete and verified against the running API:**
  - Fastify + PostgreSQL (project cluster :5434, API :4747)
  - Schema + migrations + seed (org, site, admin, device, 8 employees)
  - Device handshake (rate-limited), scan ingest (idempotent via dedupe key,
    server-time authoritative, offline syncState), template bundle, config
  - Admin auth: login/refresh/logout/me, Argon2-style scrypt hashes, revocable
    server-side sessions, failed-login audit
  - Employees CRUD + search/filter + soft deactivate/delete + enrollment with
    encrypted-at-rest templates + same-face duplicate guard
  - Attendance engine (pure module, 16 unit tests): check-in/out, min-interval
    duplicate suppression, same-day second shift gap rule, overnight shifts,
    break deduction, late/early/overtime classification, rollover
  - Corrections (add/remove check-in/out, edit timestamps/break/note/date) with
    full audit trail; corrections list endpoint
  - Attendance queries: currently-in, sessions w/ filters, per-employee history
    + totals, stats aggregates + anomaly detection, CSV export
  - Audit log endpoint, raw scan-events transparency endpoint

## In progress

- Phase 2: Flutter scanner-first client.
- Phase 3: admin experience.
- Phase 4: kiosk/device polish + responsive verification.

## Verified (smoke tests, 2026-08-11)

- device handshake → token; admin login; employees list
- check_in → checked_in; duplicate dedupe-key replay returns prior outcome;
  checkout within min-interval correctly suppressed; check_out → closed
- correction changed checkout 19:01→04:30 UTC with audit trail
- stats aggregates + employee history + CSV export (clean rows)
- offline syncState scan accepted with server time; login_failed audited

## Next

- Scaffold Flutter app: scanner-first kiosk, camera + ML Kit + TFLite
  recognition, offline queue, admin screens.
