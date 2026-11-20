# Yabil Timekeep web admin

A React + Vite + TypeScript browser dashboard for Timekeep administrators. It
shares the existing backend API and database and does not bundle or modify the
Flutter kiosk app.

## Run locally

1. Start the backend on port 4747.
2. In this directory:
   ```bash
   npm install
   npm run dev
   ```
3. Open `http://127.0.0.1:4750`. Enter the API address on the login screen
   (`http://127.0.0.1:4747` locally, or your production API).

For the production bundle:

```bash
npm run build
npm start        # serves dist/ on http://127.0.0.1:4750
```

Admin tokens are held in browser session storage. The dashboard uses
org-timezone date/time editing, so it does not depend on the admin's browser
timezone.

## Pages

- Overview: live workers, today's sessions, late/incomplete counts, overtime
  alerts, worker hours.
- Workers: search, create/edit, schedule workdays and weekly hours, pay details,
  deactivate/delete. Face enrollment is done from the mobile app.
- Attendance: date/worker/status filters, edit clock times, approve, delete,
  manual entry, mark absence, CSV export.
- Leave: record and edit leave with status.
- Payroll: monthly preview and Excel download.
- Overtime: configurable 46h/week and 184h/month defaults, projected alerts,
  schedule suggestions and Apply.
- Audit: searchable audit history.

## Production container

`Dockerfile` builds the React app and packages `dist/` into Nginx with a
`/health` endpoint and browser security headers.

In Hermes:

- root/build directory: `web-admin`
- Dockerfile: `web-admin/Dockerfile` (or `Dockerfile` when root is `web-admin`)
- container port: `80`
- health path: `/health`
- suggested domain: `timekeep.salmaan.dev`

The backend must include the web origin in `CORS_ORIGINS`. The default allows
`timekeep.salmaan.dev`, `yabil-timekeep.salmaan.dev`, the old
`faceattendance.salmaan.dev`, and the localhost dashboard.
