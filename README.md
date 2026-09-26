# FaceAttendance web admin

A separate browser dashboard for FaceAttendance administrators. It shares the
existing backend API and database but does not import, build, or modify the
Flutter kiosk app.

## Run locally

1. Start the FaceAttendance backend on port 4747.
2. In this directory run `npm start`.
3. Open `http://127.0.0.1:4750`. The login screen defaults to the same live
   backend used by the Android app: `https://faceattendance-api.salmaan.dev`.
   For local development, replace it with `http://127.0.0.1:4747`.

The web server uses only Node's standard library, so it has no packages to
install. Admin tokens are held in browser session storage and are removed when
the browser session ends or the administrator signs out.

The Overview page shows each active worker's hours for today, this week and
this month. Worker management includes web clock-in/out, employee and pay-rate
editing, manual attendance, corrections, approval, deletion, absence and leave
management. All changes use the same audited backend records as the Android
admin page.

For production, serve `public/` over HTTPS and restrict the backend CORS origin
to the website's exact HTTPS address.

## Production container

`Dockerfile` packages the dashboard as an independent Nginx service with a
health endpoint at `/health` and browser security headers. In Hermes, create a
new application from the FaceAttendance repository using:

- root/build directory: `web-admin`
- Dockerfile: `web-admin/Dockerfile` (or `Dockerfile` when the root directory
  is already set to `web-admin`)
- container port: `80`
- health path: `/health`
- suggested domain: `faceattendance.salmaan.dev`

TLS should be terminated by the existing Traefik/Hermes platform. No database,
environment variables, persistent volume, or Android app deployment is needed.
