# Local setup

## Prerequisites (this machine)

- Node 24.x, npm 11.x
- Flutter 3.22.1 (stable), Dart 3.4.1
- Android SDK at `$env:LOCALAPPDATA\Android\Sdk` (adb NOT on PATH)
- PostgreSQL 18 binaries on PATH (`initdb`, `pg_ctl` from `C:\Program
  Files\PostgreSQL\18\bin`)
- AVDs: `Kiosk_API_30_64`, `Medium_Tablet_API_30`

## 1. Database

```powershell
scripts\db_start.ps1    # initdb if needed + start cluster on :5434
scripts\db_stop.ps1     # stop only our cluster
```

Data lives in `backend/.pgdata` (gitignored). Our cluster runs on port 5434
because the machine already runs system Postgres on 5432 — never touch that.

## 2. Backend

```powershell
cd backend
npm install
npm run db:migrate
npm run db:seed        # demo org, device, admin + employees (see backend/README.md)
scripts\api_start.ps1  # detached API on :4747, logs to $env:TEMP\faceatt-api.log
```

API base URL: `http://localhost:4747`. Health: `GET /health`.

## 3. Flutter app

```powershell
cd app
flutter pub get
scripts\devices.ps1    # list adb devices / AVDs
flutter run -d <device-id>
```

The app connects to `http://10.0.2.2:4747` on Android emulators by default
(host loopback). Change `app/lib/device/config.dart` for physical devices.

## 4. Tests

```powershell
cd backend; npm test; npm run typecheck
cd app;     flutter test; flutter analyze
```

## Verifying end to end

1. `scripts\db_start.ps1`, migrate, seed.
2. `scripts\api_start.ps1`; `Invoke-RestMethod http://localhost:4747/health`.
3. Boot `Kiosk_API_30_64` with host webcam as back camera:
   `emulator -avd Kiosk_API_30_64 -camera-back webcam0`.
4. `flutter run -d emulator-5554`; the scanner should open immediately.
5. Admin: tap lock icon, sign in with seeded admin (see backend/README.md).
