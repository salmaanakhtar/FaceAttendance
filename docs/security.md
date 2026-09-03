# Security decisions

## Transport & auth

- All API traffic is HTTPS in production; local dev uses HTTP on loopback only.
- Devices authenticate with a per-device `device_key` (provisioned, high
  entropy, stored in Flutter secure storage). Device tokens are issued on
  handshake and rotated on reconnect.
- Admins authenticate with Argon2id-hashed passwords (per-user salt), JWT
  access (short TTL) + refresh token; admin sessions are stored server-side,
  revocable, and bound to a kiosk device (`admin_sessions`).
- Rate limiting on auth endpoints and scan ingest; account lockout after
  repeated failures.

## Biometric data

- Templates are AES-256-GCM encrypted at rest server-side; the encryption key
  is derived from the org secret, never stored next to the data in plaintext.
- On-device templates are encrypted at rest (secure storage backed key).
- Raw face imagery is never stored by the client or server. Only the fused
  embedding + quality metadata persists.
- Server-side authorization: every employee/template endpoint checks org
  scoping; kiosk devices can only read templates for their own org/site.

## Integrity & audit

- Raw `scan_events` are immutable; there is no update path.
- Every correction/enrollment/employee/leave mutation writes an `audit_events` row:
  old value, new value, actor, timestamp, reason, affected employee.
- Corrections cannot delete; they supersede. A "delete employee" is a soft
  delete that retains audit rows.
- Retention: audit events and scan events are retained per org policy (default
  indefinite; configurable purge job).

## Kiosk behavior

- Admin lock: scanner is default; admin requires sign-in; auto-relock after
  inactivity timeout (default 3 min) or manual lock. Lock is enforced in app
  logic AND by server session expiry (defense in depth — never hidden UI).
- No embedded secrets in APK; provisioning happens via QR code / admin
  entry at first boot.

## Input validation

- Fastify JSON Schema validation on every route; strict string length/type
  rules; parameterized SQL everywhere; no dynamic SQL.
