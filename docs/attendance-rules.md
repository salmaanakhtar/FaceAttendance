# Attendance rules

The attendance engine is a **pure module** (`backend/src/services/attendance`),
no I/O. Given immutable inputs it produces deterministic output. All rules
below are unit-tested.

## Inputs

- Raw scan events (employee, server scan time, direction hint)
- Employee schedule policy (shift start/end, grace minutes, break policy,
  overtime rules) — snapshot into the session at creation
- Org/site timezone (fixed IANA zone; DST transitions are resolved against it)

## Core rules

1. **Server time is authoritative.** `scan_time` is the server's clock at
   receipt. `device_time` is metadata only. Device clock drift is measured and
   logged per device; it never changes attendance truth.
2. **Action selection.** First daily event (no open session) → check-in.
   Subsequent events: if the previous event for this employee was a check-in
   and the min-interval since it elapsed → check-out; else duplicate.
3. **Duplicate suppression.** Per employee: events within `min_interval`
   (default 60 s, configurable) of the same direction are duplicates and are
   dropped (counted, logged) — they never create sessions.
4. **Idempotency.** Every scan event carries a device-generated `dedupe_key`
   (UUIDv4). Unique constraint on the column makes retries/sync safe: the
   second arrival is a no-op returning the first result.
5. **Overnight shifts / clock-out after midnight.** A check-out with
   `scan_time` before the employee's scheduled shift start (or before 06:00,
   whichever is later) is attributed to the *previous* work date's open
   session. A work_date session can span midnight; only one open session may
   exist at a time (per employee).
6. **Multiple shifts in one day.** A check-out closes the open session; a new
   check-in after the schedule's shift gap threshold opens a new session with
   the same work_date.
7. **Breaks.** Policy: `break_minutes` auto-deducted for shifts crossing a
   configurable duration threshold; can be disabled or manually adjusted via
   corrections.
8. **Late arrival** = check-in after `shift_start + grace`; **early
   departure** = check-out before `shift_end` (both unless justified by a
   correction); **overtime** = worked time past shift end beyond policy
   threshold.
9. **Missed check-out** = open session at day boundary (rollover). The session
   is closed by the engine as `incomplete` with an engine note, or left open
   for admin resolution; never auto-invented times.
10. **Manual corrections** create new record values + audit rows. Engine
    never re-derives over a corrected session unless explicitly re-run for the
    affected fields (only via admin action).
11. **Offline sync** events arrive with `device_time`; `scan_time` is
    assigned at server receipt — the employee's displayed time is the server
    receipt time, and the device's recorded delay is logged. `sync_state =
    offline` flags the row for transparency.

## Outputs

- `attendance_sessions` (one per shift block)
- Summary metrics per employee/period: hours worked (paid hours =
  clock-out − clock-in − breaks), late count, early count, overtime,
  incomplete count, attendance rate.

All numeric policies are expressed in `policy` JSONB snapshot inside the
session row so historical calculations never drift when policies change.
