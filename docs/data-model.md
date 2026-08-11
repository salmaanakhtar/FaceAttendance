# Data model

PostgreSQL 18, schema `public`. Migrations in `backend/db/migrations/`
(node-pg-migrate). All timestamps stored as `timestamptz` (UTC internally);
site-local time is derived at read time using the org/site timezone.

## Entities

### orgs / sites
- `orgs` — tenant (name, slug, timezone, shift policy defaults)
- `sites` — physical locations belonging to an org (name, timezone)

### devices
- `devices` — kiosk identity: `device_key` (provisioning secret), `name`,
  `site_id`, status, `clock_offset_ms` (measured drift vs server), last seen.

### employees
- `employees` — org-scoped: name, employee_code (unique), email, role, status
  (active/inactive/deleted), schedule (shift start/end, grace, break policy),
  `face_template` (encrypted 128-d embedding + model version), enrollment
  quality metadata (samples, mean distance, worst pose), `created_at`.

### scan_events (raw, immutable, append-only)
- `id`, `device_id`, `employee_id`, `scan_time` (server-authoritative),
  `device_time`, `direction` (in|out), `confidence`, `face_hash` (per-device
  local face id), `dedupe_key` (unique — device-generated UUID), `sync_state`
  (live|offline|conflict), `liveness_score`, quality flags, `created_at`.
- NEVER updated by corrections. Insert-only.

### attendance_sessions (derived)
- `id`, `employee_id`, `work_date` (site-local date), `check_in_at`,
  `check_out_at`, `source` (auto|manual), `status` (open|closed|incomplete),
  `break_minutes`, `policy` snapshot (shift config used), `derived_from`
  (raw event ids), `corrected` (bool), `corrected_at`.

### attendance_corrections (manual overrides, append-only)
- `id`, `session_id` or employee+date target, `field` (check_in|check_out|
  hours|...), `old_value`, `new_value`, `admin_id`, `reason`, `created_at`,
  `source_session_id` (session state before correction).

### audit_events
- `id`, `actor_type` (admin|device|system), `actor_id`, `action`, `target_type`,
  `target_id`, `details` (jsonb), `created_at`. Written for: corrections,
  enrollment changes, employee lifecycle, login failures, device sync,
  deletes/retention.

### admin_sessions
- `id`, `admin_id`, `token_hash`, `created_at`, `expires_at`, `revoked_at`,
  `device_id` (kiosk-bound sessions).

### pending_sync (device-side)
- Not in Postgres; stored on-device (Hive): queued scan events with
  `dedupe_key`, retried until acknowledged.

## Invariants

- `scan_events.dedupe_key` is globally unique — the idempotency anchor.
- A closed session is created/updated only by the attendance engine or by a
  correction (which first snapshots then writes a new value + audit row).
- Deleting an employee hard-removes nothing that is audited: `employees.status`
  becomes `deleted`; scan/audit rows are retained per retention policy.
- Every mutation on attendance data has a matching `audit_events` row.
