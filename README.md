# NM VIBE

NM VIBE is a completely free and open-source local-first music player. There will be no paid editions, subscriptions, premium memberships, or paid feature unlocks. Android is the primary platform; Windows is in beta.

The software licence for the repository has not yet been selected. No root `LICENSE` file is published; choosing the licence is an owner decision.

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

The repository contains the migrated Flutter app, a Node.js backend, tests, and project documentation.

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
