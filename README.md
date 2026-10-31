# NM VIBE

NM VIBE is a local-first music player project. Android is the primary platform; Windows is in beta.

## Repository layout

- `lib/core/` — app-wide services and platform abstractions
- `lib/data/` — models, music sources, repositories, and download storage
- `lib/features/` — feature-specific controllers, views, and widgets
- `lib/shared/` — providers and widgets shared across features
- `test/` — unit and widget tests organized alongside `lib/`
- `integration_test/` — end-to-end app tests
- `backend/` — Node.js API
- `assets/` — app icons, images, and third-party license texts
- `docs/` — architecture and project documentation
- `third_party/` — maintained patches to external packages
- `tool/` — project maintenance and profiling scripts

The folders are a scaffold for the planned architecture. Existing app code remains in place until each structure cleanup step is ready to be moved without behavior changes.

## Getting started

Install Flutter, then run:

```sh
flutter pub get
flutter run
```

## Checks

```sh
flutter analyze
flutter test
```
