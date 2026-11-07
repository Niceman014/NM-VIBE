# NM VIBE backend

This small Node service is retained for `GET /health` and
`GET /v1/updates/latest`. Discover search and music streaming use the app's
active sources directly. The service uses Node's built-in HTTP and fetch APIs;
there are no third-party runtime dependencies.

## Configuration

Supported environment variables are `HOST`, `PORT`, `CORS_ORIGINS`, and
`UPDATE_MANIFEST_FILE`. Update metadata can be provided using the private
manifest file described by `UPDATE_MANIFEST_FILE`. Do not put secrets in the
repository or client build arguments.

The root `render.yaml` describes a generic Node web service. Deployment and
update distribution are separate release decisions; this repository does not
assert that a production service is deployed.

## Development and checks

Use Node 20 or newer. Run `npm run start:local` to load the ignored
`backend/.env` for local development, or `npm start` on hosts that inject
environment variables. The default bind address is loopback. Configure
`HOST=0.0.0.0` only when a local-network client needs access, and restrict the
port to the private network. Run `npm test` in this folder.

## Client build notes

Discover does not depend on this service. Android update configuration and
Windows update metadata should be checked independently before distribution.
Android release builds also need a private upload keystore configured in
`android/key.properties`; do not commit that file or the keystore.
