# Status

_Last update: 2026-09-02 — v1.1.33 applies organization timezone immediately after handshake._

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
