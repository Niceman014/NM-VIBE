# NM VIBE music API

This small Node service keeps the Jamendo client ID out of the Flutter app. It
provides `GET /health`, `GET /v1/music/search?q=&page=&limit=`, and
`GET /v1/music/stream/:trackId`. It uses only Node's built-in HTTP and fetch
APIs; there are no third-party runtime dependencies.

## Jamendo configuration

The owner-provided Jamendo dashboard shows the application as live with
Commercial usage. Its client ID is configured only in the ignored local
`backend/.env`. Set the same ID as a secret environment variable on the host;
never put it in Flutter build arguments or source control. The dashboard
screenshot exposed a separate client secret; this service does not use it.

Jamendo is stream-only in NM VIBE. The backend never returns Jamendo download
URLs, even if Jamendo's per-track API field suggests a download is available.

## Deploy with Render

The repository-root `render.yaml` describes the backend service. Create a
Blueprint from this repository in Render, provide `JAMENDO_CLIENT_ID` when
prompted, and wait for the service to become healthy. The service uses a paid,
always-on Render plan; review hosting charges before creating it. Render
provides the public HTTPS URL after deployment. Set `CORS_ORIGINS` to the exact
browser origins only if the Flutter web build will call this API.

Build the clients with the deployed HTTPS URL (replace the example URL):

```powershell
flutter build apk --release --dart-define=BACKEND_URL=https://your-service.onrender.com
flutter build windows --release --dart-define=BACKEND_URL=https://your-service.onrender.com
```

Android release builds also need your private upload keystore configured in
`android/key.properties`. Do not commit that file or the keystore.

Until the backend is deployed and the client is rebuilt with its HTTPS URL,
Discover intentionally shows that online music is not configured. The
installed app cannot use the local development backend on your PC.

## Development and checks

Use Node 20 or newer. Run `npm run start:local` to load the ignored
`backend/.env` file for local development. To let a physical phone on the same
Wi-Fi reach the PC backend, set `HOST=0.0.0.0` and `PORT=8787` in the local
environment before starting it; allow the port through Windows Firewall only
for your private network. Run `npm start` on hosts that inject environment
variables. Run `npm test` in this folder.

For the Android emulator use `--dart-define=BACKEND_URL=http://10.0.2.2:8787`.
For a physical phone use the PC's private LAN IPv4 address, for example
`--dart-define=BACKEND_URL=http://192.168.1.25:8787`. Debug builds accept only
loopback/private HTTP addresses; release builds require HTTPS.
