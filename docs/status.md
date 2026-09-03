# Status

## v1.2.16 — Attendance deletion and cleaner labels

- Worker session details now include **Delete time entry**. Deletion removes the
  derived entry from dashboards, totals, payroll, exports, and absence checks,
  while retaining raw scans and a server-side audit event.
- Admin-created and corrected times no longer display redundant `manual` or
  `corrected` badges. The audit data remains available internally.
- Includes the backend migration required for explicit manual absences, fixing
  the `invalid leave type` response after the backend is deployed.
- Release APK: `app/releases/FaceAttendance-v1.2.16-lan.apk`.

## v1.2.15 — Visible manual absence action

- Moved **Mark absent for this date** into the manual-entry form as a
  full-width red button beneath the worker and work-date fields, keeping it
  visible on narrow phone and kiosk screens.
- Release APK: `app/releases/FaceAttendance-v1.2.15-lan.apk`.

## v1.2.14 — Manual absence entry

- The manual attendance dialog now includes a **Mark absent** action for the
  selected worker and work date.
- Manual absences are stored as approved, audited absence records rather than
  fabricated scan events or zero-length attendance sessions.
- Release APK: `app/releases/FaceAttendance-v1.2.14-lan.apk`.

## v1.2.13 — Reliable manual time entry

- Manual check-in and optional check-out now save atomically in one backend
  transaction, preventing half-saved open shifts when the second request fails.
- Closed historical entries can be recorded even when an older incomplete
  shift exists, and failures show the concise API reason in the app.

## v1.2.12 — Worker creation and leave rollout fixes

- Worker forms now scroll above the keyboard, validate numeric kiosk codes,
  and show concise API validation messages instead of raw Dio exceptions.
- Codes belonging only to deleted, hidden workers can be reused safely; codes
  on active or inactive workers identify the conflicting worker by name.
- Automatically generated worker codes are numeric so they can be entered on
  the kiosk keypad.
- The Leave page now handles an older backend's missing route without leaving
  a permanent raw 404 error on screen, while retaining pull-to-refresh.
- Production backend startup now applies pending database migrations before
  starting the API, keeping new routes and their schema in sync.

## v1.2.11 — App-side Yabil timezone safeguard

- The app now replaces the legacy Yabil `Asia/Karachi` setting with
  `Africa/Johannesburg` during startup and online configuration refresh.
- The corrected timezone is saved on the device, so the kiosk remains correct
  while offline and does not depend on the backend migration being deployed.

## Yabil timezone correction — 2026-09-03

- Corrected legacy Yabil organization and site records from
  `Asia/Karachi` (UTC+5) to `Africa/Johannesburg` (UTC+2), fixing kiosk
  clocks that displayed three hours ahead.
- Corrected the demo seed so new environments use the South African timezone.

## v1.2.10 — Server-anchored app time

- Replaced the persisted raw clock offset from v1.2.9 with a monotonic clock
  anchored directly to the backend timestamp. This prevents a stale offset
  from being applied again after the Android clock changes.
- v1.2.9 offsets are deleted automatically on launch.
- Release APK: `app/releases/FaceAttendance-v1.2.10-lan.apk`.

## v1.2.9 — Initial server-time synchronization

- The app now refreshes the organization timezone at every online startup
  instead of relying only on timezone data saved during provisioning.
- Live kiosk clocks and admin "today/now" actions use a persisted offset from
  the backend's authoritative clock, so an incorrect Android device clock no
  longer shifts the displayed attendance time.
- Historical attendance timestamps continue to be stored by the backend in
  UTC and displayed in the configured organization timezone.
- Superseded by v1.2.10 because a persisted raw offset could become stale.

## v1.2.8 — Absence and leave tracking

- Dashboard worker totals now show weekly and monthly absent-day and approved-leave-day counts, plus an organization-wide monthly absence total.
- Added an admin Leave area for recording and editing annual, sick, unpaid, and other leave with pending, approved, rejected, and cancelled states.
- Approved leave excuses a completed scheduled day from absence; today, future dates, pre-employment dates, and unscheduled weekdays are excluded.
- Employee forms now configure scheduled workdays (Monday–Friday by default) and preserve existing schedule policy fields during edits.
- Leave changes are audited server-side. Database migration: `003_employee_leave.sql`.
- Release APK: `app/releases/FaceAttendance-v1.2.8-lan.apk`.

## v1.2.7 — Visible code-punch confirmation

- Successful code punches now show a prominent floating confirmation for five seconds, above the scrollable keypad content.
- The confirmation clearly identifies check-in versus check-out, the worker name, and the organization-local recorded time; queued offline punches are labeled explicitly.
- Invalid, duplicate, and failed punches use the same visible banner treatment so kiosk users are never left without feedback.
- Release APK: `app/releases/FaceAttendance-v1.2.7-lan.apk`.

## v1.2.6 — Manual time display refresh

- Corrected check-in/check-out values now update immediately on the session screen after an audited manual edit.
- Attendance timestamps are formatted in the configured organization timezone instead of the Android device timezone, keeping displayed values consistent with the picker and worked-hour calculations.
- Release APK: `app/releases/FaceAttendance-v1.2.6-lan.apk`.

## Dashboard time editing — 2026-09-02

- Check-in and check-out values in the dashboard shift list now open their date/time picker directly; the session cards are also tappable to edit or add a missing punch.
- Removed the redundant check-in/check-out edit and add actions from underneath the session summary.

## v1.2.5

- Corrected the dashboard hours table to always calculate Today, This week, and This month from their own date ranges, regardless of the selected detail view.
- Release APK: `app/releases/FaceAttendance-v1.2.5-lan.apk`.

## v1.2.4

- Admin dashboard now shows a worker-hours table with separate Today, This week, and This month totals for every active worker.
- Each total is tappable to open that worker's editable attendance sessions.

## v1.2.3

- Kiosk worker-code screen now has a permanent touch number keypad under the code field and a dedicated Punch Time button beneath it.
- Clear and backspace controls make correcting a code quick without opening the device keyboard.

## v1.2.2

- Added a kiosk refresh button for worker codes.
- Worker roster requests time out quickly and fall back to the securely cached roster, avoiding long waits when the network is unavailable.

## v1.2.1

- Cached the authenticated active-worker roster in Android Keystore-backed storage so code punches remain usable offline after the first roster sync.
- Cached roster data contains only worker IDs, names, and codes; no biometric templates or images.

## Code kiosk rollout

- The active kiosk interaction is code-based punching. Face recognition files and legacy enrollment data remain in the repository for compatibility, but are not initialized or used for worker attendance on the kiosk.

## v1.2.0 — code-based kiosk punching

- Replaced the kiosk face-scanner surface with a worker-code entry flow: enter a code and press Enter/Punch to alternate check-in and check-out through the server attendance engine.
- Added an authenticated device roster endpoint containing active worker IDs, names, and codes (no biometric data), including workers who were never enrolled for face recognition.
- Code punches retain server-authoritative timestamps, idempotency, encrypted offline queueing, status feedback, haptics, and Welcome/Goodbye voice confirmation.

## v1.1.45

- Audit failures now provide a retry action instead of a dead-end message.
- Audit events display readable action labels, actor context, and compact detail fields for faster review.

## v1.1.44

- Liveness treats missing ML Kit eye probabilities as neutral frames, so a device without eye signals cannot fabricate a blink from a closed-eye transition.
- Added regression coverage for that camera/device behavior.

## v1.1.43

- Attendance controls now reflow responsively instead of forcing date, export, payroll, and approval actions into one overflowing row.
- Dashboard summary cards reflow to a readable two-column layout on narrow screens.

## v1.1.42

- Camera NV21 conversion honors chroma row padding and per-plane pixel strides, improving ML Kit reliability across Android camera implementations.
- Added regression coverage for padded interleaved and planar chroma layouts.

## v1.1.41

- Reset liveness state for every scan and count only complete open/closed/open blink cycles, preventing one worker's liveness from carrying into the next scan.
- Dashboard worker totals now show planned-hours progress for week/month and retain a clear one-tap edit affordance.
- Manual time entry adds one-tap “Now” controls for check-in and optional check-out, while preserving the open-shift workflow.

_Last update: 2026-09-02 — v1.1.40 release candidate; analyzer diagnostics are clean._

## v1.1.40

- Cleaned up remaining Dart analyzer diagnostics across scanner and admin screens.
- Behavior is unchanged from v1.1.39; this release provides a fresh APK with the complete current source.

## Attendance filter timezone — 2026-09-02

- Today/week/month shortcuts and custom attendance date pickers now calculate calendar boundaries in the organization timezone, avoiding off-by-one-day registers for remote admins.

## Large-organization correction refresh — 2026-09-02

- Session edits now refresh against the backend’s 500-session window, reducing stale results for organizations with larger attendance registers.

## Correction screen consistency — 2026-09-02

- After an add-missing-punch correction, the session detail view now follows the server-returned session ID and displays the newly created or updated session immediately.

## Missing event corrections — 2026-09-02

- “Add missing check-in” and “Add missing check-out” now open the date/time picker and send the correct employee-level add-event request, so admins can repair absent punches from a session without a backend validation failure.

## Offline scan feedback — 2026-09-02

- A recognized scan queued during network loss now uses the locally selected direction for immediate check-in/check-out status, haptic confirmation, and employee-specific Welcome/Goodbye voice feedback. Server reconciliation remains authoritative when connectivity returns.

## Scanner startup reliability — 2026-09-02

- Scanner initialization is now single-flight: repeated retry taps cannot overlap camera/model startup or create competing image streams.

## Provisioning timezone — 2026-09-02

- A newly provisioned kiosk or refreshed device handshake now applies the organization timezone immediately, without requiring an app restart.

## Time edit correctness — 2026-09-02

- Manual-entry and session-edit pickers now use the organization IANA timezone and send explicit UTC timestamps, avoiding incorrect hours when an admin device has a different timezone.

## Manual checkout recovery — 2026-09-02

- Admin manual check-out now accepts both open and rolled-over incomplete sessions, allowing a missed end-of-day punch to be corrected from the same workflow.

## Worker coverage — 2026-09-02

- Dashboard week/month totals now include every active worker, including those with zero recorded hours, so missing attendance cannot be hidden by an empty session list.

## Scan response time — 2026-09-02

- Live scan submissions use a three-second request deadline and then enter the encrypted offline queue, instead of waiting through the generic API timeout when the network is unavailable. Server time remains authoritative when the queued event is delivered.

## Dashboard editing — 2026-09-02

- Week/month worker totals are now interactive. Tapping a worker opens their shifts for the selected period, with a direct edit affordance for each session.

## Update safety — 2026-09-02

- APK upgrades now retain the device provisioning key, server token, organization identity, and offline scan queue. Face templates remain version-gated and refresh from the server; upgrades no longer unexpectedly return a configured kiosk to the provisioning screen.

Release tags now publish their matching `app/releases/FaceAttendance-<tag>-lan.apk`
as a GitHub Release automatically, which is the source used by kiosk auto-update.

## Scanner and dashboard usability — 2026-09-01

- Scanner no longer requires an impossible blink signal when a camera/ML Kit
  build does not expose eye probabilities; face quality and multi-sample
  matching gates remain active.
- NV21 metadata now supplies the camera row stride to ML Kit for more reliable
  frame decoding across Android devices.
- Dashboard includes per-worker worked-hour totals for the current week or
  month, with a one-tap period switch.

## Scan latency — 2026-08-31

- Face detection runs in fast mode and progressive matching no longer scans the
  full employee template list on every captured frame; it evaluates at the
  final decision point instead.
- The four-frame liveness minimum remains unchanged to preserve anti-spoofing
  and recognition quality.

## Manual time entries — 2026-08-31

- Attendance admins can create a complete historical entry by selecting a
  worker, date, check-in, check-out, and reason. Both events are audited and
  derived totals are recalculated immediately.

## Kiosk feedback and admin operations — 2026-08-31

- Successful scans now provide employee-specific voice confirmation: “Welcome
  [name]” on check-in and “Goodbye [name]” on check-out.
- Face detection uses the fast camera mode while retaining embedding quality
  gates and ambiguity rejection, reducing kiosk recognition latency.
- Admin employee details now expose soft-delete (attendance/audit history is
  retained), and the audit list shows target/details context.
- Added an auditable payroll-period CSV gross-pay estimate using each worker’s
  configured `schedule.hourlyRate`; it is intentionally not a statutory tax
  payslip until tax rules and deductions are configured.

## Timesheet editing and totals — 2026-08-31

- Manual check-in, check-out, work-date, note, and break edits now
  immediately recalculate worked, late, early, and overtime minutes from the
  corrected session inputs.
- Attendance now shows period-level total worked time, overtime, and open-shift
  counts above the register.
- Session correction UI now supports editing unpaid break minutes, with the
  same required reason and audit trail as timestamp edits.
- This follows established timesheet workflows where managers edit start/end
  and breaks, review calculated totals, and retain an approval/audit history.

## Enrollment reliability + operations — 2026-08-29 / v1.1.3 APK — 2026-08-31

- Fixed an enrollment loop that captured eight near-identical frames before
  asking for pose variety, rejected the batch, and could repeat forever.
  Enrollment now guides the person through front, both side poses, and front
  again, with 350 ms spacing between accepted samples.
- Face sharpness crops now clamp ML Kit boxes to the camera frame, preventing
  edge-of-frame `RangeError` failures; luma uses all BGR channels.
- Added an admin “Needs attention” inbox for missed check-outs, late arrivals,
  early departures, and overtime. Items open the session correction view.
- Dashboard “Today” totals are now actually scoped to the organization-local
  current date; the exception inbox is scoped to the latest 14 days.
- Added `docs/workforce-management-roadmap.md`, benchmarked against Deputy,
  UKG, and QuickBooks Time. Payroll-ready approval/break handling is Phase 1.
- Backend verification: 18 tests pass and TypeScript typecheck passes.
- Flutter verification: analyze clean; all 33 Flutter tests pass. Release APK
  rebuilt: `com.faceattendance.face_attendance`, version `1.1.3` (code 5),
  58.1 MB. Artifact: `app/releases/FaceAttendance-v1.1.3-lan.apk`.
- Real-camera enrollment gauntlet is still pending on a physical/emulator
  device; this build was produced from the isolated Flutter 3.22.1 + Android
  SDK 34 toolchain.
- Duplicate-face enrollment checks now ignore inactive employees (their faces
  are already excluded from scanner matching), while active conflicts identify
  the employee to re-enroll in the error message.
- Deactivating an employee now clears their biometric template; reactivation
  requires fresh enrollment.

## Accuracy rework (v2) — 2026-08-19

Reported: enrolled users' check-ins failing silently; two unrelated people
being confused (enrollment said "already enrolled"; a scan checked in as the
other person). See `docs/accuracy.md` for the full investigation.

Root causes fixed:
- **Channel order**: the embedding tensor was RGB; InsightFace models are
  trained on BGR. Fixed in `app/lib/recognition/embedder.dart`.
- **Accept threshold 0.38** was inside the impostor tail (measured impostor
  cosine peaks ~0.17 even under heavy degradation). Raised to **0.45** with
  ambiguity margin **0.10** (`app/lib/config.dart`).
- **Template versioning**: new `templateVersion = 2`; the app and server only
  match/enroll against same-version templates so stale (buggy-pipeline)
  templates can never be confused with new ones. **All users must re-enroll.**
- **Diagnostics**: unknown/ambiguous scans now show a clear card with the
  match score; a stalled recognition engine surfaces an error instead of
  hanging on "Scanning…".

## v1.1.1 hotfix — 2026-08-22 (current)

Field bug: a correctly enrolled user's scan showed **"Unclear match"** at a
genuine **match 86%**. Root cause: `matchEmbedding` computed the ambiguity
margin between the top-1 and top-2 **candidates**, but a genuine scan scores
high against several candidates of the SAME employee (fused template +
samples), so the "rival" was the same person's own sample — margin ~0.02
always flagged ambiguous. Fixed to compare the two best **distinct
employees**. No re-enrollment needed (template v2 unchanged).

- GitHub release **v1.1.1** (auto-update source); local sideload
  `app/releases/FaceAttendance-v1.1.1-lan.apk`.

## v1.1.0 deployed — 2026-08-22

- Backend: container `hermes-app-faceattendance-api` already running commit
  `827b776` (auto-built by the hermes platform; verified the v2 same-face
  guard in the live container; API healthy at
  https://faceattendance-api.salmaan.dev).
- App: GitHub release **v1.1.0** published (auto-update source); local
  sideload copy `app/releases/FaceAttendance-v1.1.0-lan.apk`.
- Build infra: Kotlin bumped 1.7.10 → 1.8.22 (core-ktx metadata required it).

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
