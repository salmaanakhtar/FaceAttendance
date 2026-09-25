# FaceAttendance web admin

A separate browser dashboard for FaceAttendance administrators. It shares the
existing backend API and database but does not import, build, or modify the
Flutter kiosk app.

## Run locally

1. Start the FaceAttendance backend on port 4747.
2. In this directory run `npm start`.
3. Open `http://127.0.0.1:4750` and enter the backend address, for example
   `http://127.0.0.1:4747`.

The web server uses only Node's standard library, so it has no packages to
install. Admin tokens are held in browser session storage and are removed when
the browser session ends or the administrator signs out.

For production, serve `public/` over HTTPS and restrict the backend CORS origin
to the website's exact HTTPS address.
