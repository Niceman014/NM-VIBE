# NM VIBE Music API

This Node.js service currently provides a health endpoint for deployment checks.

## Run locally

```sh
npm start
```

The service listens on `PORT` (default `3000`). `GET /health` returns `{"status":"ok"}`.

## Test

```sh
node --test
```
