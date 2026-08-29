# Workforce management roadmap

_Reviewed: 2026-08-29._

FaceAttendance is a site-bound biometric time clock, not yet a complete payroll
or workforce scheduling suite. The goal is to make captured time trustworthy,
easy to review, and ready for payroll while preserving immutable raw events.

## Product benchmark

Current leading workforce systems converge on the same operating loop:

1. plan work with schedules, availability, leave, roles, sites, and demand;
2. capture actual time, breaks, location/site, and job or task;
3. compare planned versus actual time and surface exceptions in real time;
4. let managers correct and approve timesheets with a complete audit trail;
5. send only approved time to payroll and job-costing systems;
6. analyze overtime, absence, coverage, labor cost, and recurring patterns.

Official product references used for this comparison:

- Deputy: time capture, live attendance, schedule comparison, missing punches,
  no-shows, break compliance, approvals, scheduling, leave, and payroll export:
  https://www.deputy.com/features/time-and-attendance
- UKG: time/attendance, exception and compliance management, scheduling,
  forecasting, absence management, and real-time analytics:
  https://www.ukg.com/products/workforce-management
- QuickBooks Time: kiosk/mobile capture, schedules, breaks, time off, approvals,
  projects/job costing, payroll, GPS, and geofencing:
  https://quickbooks.intuit.com/time-tracking/

GPS is not the first priority for this app: a provisioned kiosk already belongs
to a known site and facial verification proves who is present at that kiosk.
If mobile/field clocking is added later, location must be collected only while
on the clock and governed by an explicit organization policy.

## Delivery phases

### Phase 0 — trustworthy capture and operational visibility (implemented)

- server-authoritative time, immutable raw scans, idempotent offline sync;
- face enrollment with staged front/both-side samples and visible diagnostics;
- deterministic sessions, lateness, early departure, overtime, breaks, and
  missed-checkout rollover;
- live “who is in” dashboard and a manager exception inbox;
- audited corrections and CSV export.

### Phase 1 — payroll-ready timesheets (next)

- explicit paid/unpaid break punches instead of deduction-only breaks;
- timesheet lifecycle: open → needs review → approved → exported/locked;
- pay periods and bulk approval, with correction reopening rules;
- exception resolution/attestation with manager reason and audit event;
- payroll export profiles and stable external employee/pay-code mappings.

### Phase 2 — planned versus actual attendance

- versioned schedules by weekday/date, multiple shifts, roles and sites;
- no-show, unscheduled work, late start, early finish, missed/short break, and
  overtime-before-approval rules;
- leave types, balances, requests and approved absence suppression;
- notifications for upcoming shifts and unresolved exceptions.

### Phase 3 — labor operations

- departments, jobs/tasks, labor allocation, pay rates and job costing;
- availability, open shifts, shift swaps, manager coverage tools;
- demand inputs, staffing forecasts, budget-versus-actual labor dashboards;
- documented payroll/HR integrations and webhooks.

## Non-negotiable controls

- Raw `scan_events` remain append-only; review state belongs to derived records.
- Every approval, rejection, correction, schedule edit, and export is audited.
- Policy and schedule versions are snapshotted so old pay results never drift.
- Biometric templates and location data follow least-privilege access and
  explicit retention policies; raw face imagery is never stored.
- No feature is called complete until backend rules are deterministic and
  tested and the real kiosk flow has passed an emulator/device gauntlet.
