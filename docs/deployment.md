# Deployment and database setup

This is the production rollout for the Timekeep rebuild. It covers the
`yabil-timekeep` database, AWS Rekognition, the React web admin, and the Android
kiosk.

## 1. Database

The target database name is **`yabil-timekeep`**. The legacy deployment used
`faceattendance`; keep the old database until the cutover is verified.

```bash
# on the VPS, as the postgres superuser
CREATE ROLE yabil_timekeep LOGIN PASSWORD '<strong-password>';
CREATE DATABASE "yabil-timekeep" OWNER yabil_timekeep;
```

If migrating from the existing `faceattendance` database:

```bash
pg_dump -U postgres -Fc faceattendance > /srv/backups/faceattendance-pre-timekeep.dump
pg_restore -U postgres -d "yabil-timekeep" --no-owner --role=yabil_timekeep \
  /srv/backups/faceattendance-pre-timekeep.dump
```

Then update the app environment:

```dotenv
DATABASE_URL=postgres://yabil_timekeep:<password>@<postgres-host>:5432/yabil-timekeep
```

Run migrations:

```bash
npm run db:migrate
```

New migration: `008_rekognition_faces.sql` creates `employee_faces`.

If reusing the existing `hermes-db-faceattendance` container, create the new
database inside it and point `DATABASE_URL` at it. Do not delete
`faceattendance` until the new app has been verified.

## 2. AWS Rekognition

Region: **`sa-east-1` (São Paulo)**. Rekognition is not available in
`af-south-1`; São Paulo is the closest supported region.

The VPS is not EC2, so use a dedicated IAM user's **access keys** in the hermes
secret store:

```dotenv
AWS_REGION=sa-east-1
AWS_ACCESS_KEY_ID=<secret>
AWS_SECRET_ACCESS_KEY=<secret>
REKOGNITION_COLLECTION_PREFIX=yabil-timekeep
REKOGNITION_SIMILARITY_THRESHOLD=90
REKOGNITION_AMBIGUITY_MARGIN=2
```

Minimum IAM policy and privacy notes are in [`rekognition.md`](./rekognition.md).
If the VPS is later moved to EC2/ECS, switch to an instance/task role and remove
the keys.

Deploy the backend with the new variables. On the first enrollment the backend
creates `yabil-timekeep-<org-uuid>` automatically.

## 3. Backend

```bash
cd backend
npm ci
npm run db:migrate
npm run typecheck
npm test
npm run dev      # local only; use the hermes process in production
```

Production requirements:

- `DATABASE_URL`
- `JWT_SECRET` (32+ random characters)
- `ORG_ENCRYPTION_KEY` (32+ random characters; legacy template data)
- `CORS_ORIGINS` including the web admin origin
- AWS variables above

`/health` must return `{"ok":true}`.

## 4. Web admin

`web-admin` is now a React app. The old vanilla `public/` files are removed.

```bash
cd web-admin
npm ci
npm run build
```

Deploy `web-admin/dist/` behind Nginx (the included Dockerfile does this), or
run `npm start` for a local production check. The container health path is
`/health`.

In hermes:

- build/root directory: `web-admin`
- Dockerfile: `web-admin/Dockerfile`
- port: `80`
- domain: `timekeep.salmaan.dev` (or your chosen host)

Confirm the domain is in `CORS_ORIGINS`.

## 5. Android kiosk

The kiosk now uses face-first check-in with worker-code fallback.

```bash
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Set the API base at build time if needed:

```bash
flutter build apk --release \
  --dart-define=API_BASE=https://<api-host>
```

After installing the APK:

1. Provision/confirm the kiosk device key.
2. Sign into the mobile admin.
3. Open each worker and **Re-enroll face** (legacy MobileFaceNet templates
   cannot be imported into Rekognition).
4. Test a real face check-in and a worker-code fallback while offline.
5. Confirm `scan_events` has the new rows and `confidence` values.

## 6. Verification checklist

- [ ] `yabil-timekeep` database restored and migrations applied.
- [ ] Backend `/health` is healthy.
- [ ] AWS collection created after the first enrollment.
- [ ] One worker enrolled and one face scan succeeds.
- [ ] Unknown face is rejected.
- [ ] Worker-code fallback works with the network disabled.
- [ ] React login, overtime page, time edit, and payroll download work.
- [ ] `employee_faces` is cleared when a worker is deactivated/deleted.
- [ ] Backups include the database and any legacy attachments.

## 7. Rollback

- **Backend:** redeploy the previous image and point `DATABASE_URL` back at the
  preserved `faceattendance` database.
- **Web admin:** redeploy the previous Nginx image.
- **Android:** install the previous APK from the GitHub release.
- **Rekognition:** old legacy templates are still in `employees.face_template`;
  the previous APK uses them. Do not delete `faceattendance` or the old template
  column until the rollout is accepted.
