# NM VIBE — product audit and production-readiness roadmap

**Audit date:** 2026-11-07  
**Repository state:** `main`, with pre-existing modified and untracked files. No changes were reset, staged, committed, or pushed for this audit.  
**Supported targets:** Android (primary), Windows (beta). Other platform folders are not release commitments.

This is an evidence-based audit of the current workspace, not a claim that NM VIBE is complete or production-ready. “Implemented” means code and/or tests exist; it does not mean live provider, real audio output, or physical-device acceptance has passed.

## Executive assessment

The application has substantial working foundations: local-library persistence and scanning, playlists, a player/queue, Discover across local files and Internet Archive, provider-gated downloads, recovery-oriented download metadata storage, settings, an update subsystem, and a tested Node backend. Windows Release builds. The 127 Flutter tests and 13 backend tests pass in this environment when backend loopback is allowed.

Production readiness is blocked by unresolved package identity and signing, an unpublished software licence, no verified backend deployment or release pipeline, incomplete download lifecycle, update-policy/security gaps, unverified Android device behavior, and no independently verified audio output. Fresh Dart analysis and Flutter tests pass. Android Release remains blocked by Kotlin incremental-cache finalization in the standard Flutter build and an Android lint/JDK compatibility error in the serial nonincremental diagnostic build.

## Feature inventory

| Area | Classification | Evidence and limits |
| --- | --- | --- |
| Local library and storage | Implemented; partially verified | Sembast song/playlist stores, tag readers, artwork handling, Windows folder scan, Android MediaStore scan, and legacy data migration/tests exist. Database/schema tests pass. Physical Android scanning/permissions and upgrade data preservation have not been tested on a device. |
| Library browsing | Implemented; partially verified | Library, artist and album screens, sorting, favorites, recent-play providers and lazy list tests exist. Several current UI edits are uncommitted and were preserved. Real large-library profiling is limited to isolated search tests and a 5,000-row widget test. |
| Playlists | Implemented; partially verified | Sembast CRUD, membership, ordering and playback integration exist. No import/export, cloud backup, or cross-device sync is implemented. |
| Discover/search | Implemented; partially verified | Active local and Internet Archive adapters, ranking, normalized matching, page requests, conservative duplicate suppression, progressive source updates, stale-generation protection and error/empty/loading UI have automated coverage. Live Windows checks found useful results, but Archive `mediatype:audio` mixes music with spoken-word/radio. Suggestions/history, source filters and uncancellable in-flight requests remain gaps. Full pagination/error matrix is not yet verified. |
| Internet Archive provider | Implemented; live subset verified | Search, metadata, streaming and per-item download checks are present. A live “moonlight” query returned music plus spoken-word-style items; local and Archive timer progress was observed. Timer progress is not independent audible-output verification. Rights metadata may be incomplete or wrong; per-item review remains necessary. Cache is in-memory without a TTL/cap. |

| Audius and radio | Missing/placeholder | Source-named files are not registered in `musicRepositoryProvider`; no live integration is active. Rights, API access and reliability are not approved. |
| Local/online playback and queue | Implemented; partially verified | Long-lived audio handler, source routing, queue controls and retry/skip recovery exist. Windows Release builds and earlier interactive tests observed local and Archive player timers advancing. No calibrated or independent audible-output check, interruption/recovery matrix, Android playback or background/lock-screen test has passed. Queue is a snapshot of results visible at play time. |
| Offline downloads | Implemented; manual acceptance outstanding | Discover provides source/item-gated save actions and per-track task state/progress, retry/cancel, eligibility explanations, and navigation to Downloads. The manager validates existing file sizes and allows explicit redownload. The Archive source does not trust an unregistered/mismatched final-name file. Managed deletion is constrained to the managed root, with tests proving external/unrelated files are preserved. Downloads displays file size and distinguishes missing from mismatched files. Automated coverage passes. Task state is in-memory, pause/resume is unsupported, trusted-source hash validation is not implemented, and restart/offline-device/audio-output acceptance remains outstanding. |
| Lyrics, equalizer, sleep timer | Implemented; not production-verified | Feature code/screens and selected tests exist. Provider behavior, real device audio-session behavior, background playback and platform-specific controls need device verification. |
| Settings and accessibility | Partially implemented | Theme, library, playback, storage, update and About sections exist; widget smoke tests cover selected text-scale/narrow cases. Full screen-reader, keyboard, narrow Android and permission-denial QA is absent. |
| App updates | Partially implemented; policy/security mismatch | Android strategy delegates to Play/update-page behavior. Windows strategy downloads a manifest-provided installer, validates HTTPS, size and SHA-256, then launches it. Backend returns update metadata with placeholder configuration. No verified deployment, hosted artifact, signing identity, signature verification independent of the manifest origin, rollback or end-to-end installation exists. `docs/UPDATES.md` says store handoff/no self-updater while current code includes a Windows installer flow and UI “Install update”; align policy before release. |
| Node backend | Implemented; deployment unverified | Health and update metadata routes, input validation, rate limits, an in-process update cache and backend tests exist. Tests pass when localhost is permitted. Render blueprint is only a template; no live health endpoint/deployment was verified. Rate limits and caches are per process. |
| Updates/releases/CI | Mostly missing | `flutter_version.txt` selects Flutter `3.50.0-0.1.pre` (beta). No CI workflow is present (`.github/workflows` only has `.gitkeep`). No verified Windows installer packaging/code signing or release artifact, and no Android signing setup. Remote GitHub lookup failed DNS; repository release state could not be confirmed. |
| Open-source/legal/privacy | Blocked on owner decisions | No root `LICENSE` exists. The product is described as open source, but a legal software licence has not been selected. No privacy policy or complete third-party licence inventory was verified. |
| Security/secrets | Partially reviewed | `.gitignore` excludes `.env`, signing files and `google-services.json`; local `backend/.env` exists and is not tracked. Two provider-specific lines were removed without reading values. Deployed host settings were not accessible from this workspace, and a complete historical secret scan was not conclusive. |
| Android package/release | Known release blocker | `android/app/build.gradle.kts` still uses `applicationId = "com.example.nm_vibe"` and release signing uses the debug signing config. The project's naming guidance lists `com.nmnext.nmvibe`, but package identity and whether this app has been distributed/has user data must be confirmed before changing it. A package ID change is not a normal in-place Android update. |
| Windows platform | Build verified; current download UI not manually verified | Current `flutter build windows --release` succeeded. The executable was not open to the interaction surface during the download reliability follow-up. Physical keyboard, live transfer, restart, offline playback, and audio-output checks are still needed. |

## Current verification snapshot

- `flutter --version`: Flutter 3.50.0-0.1.pre, channel beta; direct Dart executable worked. Flutter requires access to a lock/cache under the SDK installed outside the project, so Flutter commands need authorized access to that SDK path.
- `flutter analyze`: passed with no issues after removing the confirmed redundant `dart:async` import in `test/data/repositories/sembast_search_benchmark_test.dart`.
- `flutter test`: passed all 142 tests after the Discover-to-offline reliability follow-up.
- `node --test` in `backend/`: passed, 13 tests with loopback permission; without it, sandbox networking rejected localhost sockets.
- `flutter build windows --release`: passed after the download follow-up; produced `build/windows/x64/runner/Release/nm_vibe.exe`.
- `flutter build windows`: passed and produced `build/windows/x64/runner/Release/nm_vibe.exe`; this latest build was not manually relaunched.
- `flutter build apk --release`: standard Flutter build failed in multiple plugin Kotlin tasks with “Could not close incremental caches”. A direct Gradle diagnostic with one worker, incremental compilation disabled and in-process Kotlin compilation passed those tasks, then failed at `:url_launcher_android:lintVitalAnalyzeRelease` with `NoSuchMethodError: java.util.List.removeLast()` from Android lint. The active Java runtime is Temurin 17.0.20; that method was added in Java 21, so the lint component and selected runtime are incompatible. These flags were diagnostic only; no Gradle settings or dependencies were changed. Retry with a compatible JDK (such as the matching Android Studio JBR, if installed) before changing project configuration. Gradle also warned the local patched `on_audio_query_android` plugin applies Kotlin Gradle Plugin; Flutter warns future versions will require built-in Kotlin migration.
- `git diff --check`: passed with Git LF-to-CRLF conversion warnings.
- Android device: `adb devices` could not start its server (`ADB server didn't ACK`); no emulator executable was found on PATH. No Android device verification is claimed.
- Live Internet Archive: “moonlight” returned relevant music plus spoken-word-style items; partial search success observed. A provider error/rate limit and multiple successful additional pages were not forced/confirmed.
- Backend deployment and GitHub release endpoints were not verified; network DNS/remote access did not permit a repository query.

## Phase 2 provider cleanup

The inactive provider adapter, its app registration and playback fallback, backend music routes, configuration names, deployment environment entries, obsolete tests, and stale text references have been removed. The backend health and update routes remain. Existing generic song/download rows were preserved without schema changes. Two matching lines were removed from the ignored local environment file without reading values; deployed environment settings were not inspected. Automated checks and the Windows build must be rerun after this cleanup.

## Dependency-ordered roadmap

### Phase 0 — Decisions and build baseline (current gate)

1. Analyzer finding is fixed; keep Dart analysis and tests green.
2. Retry Android Release using a Java runtime compatible with the installed Android lint component; then investigate the Kotlin cache failure separately. Do not delete caches or change Gradle/Kotlin versions without evidence.
3. Confirm Android application ID and whether any `com.example.nm_vibe` build has been distributed or contains user data. Set one stable ID only after that answer and a migration/upgrade plan.
4. Select the repository software licence; add it only after owner approval. Prepare a privacy/data-handling statement and inventory third-party notices.
5. Confirm that any previously exposed provider credential has been revoked in its service dashboard.
6. Decide the update policy (store-managed versus app-managed) and Windows signing/trust model. Current source/docs disagree.

**Exit criteria:** analyzer and all tests pass; Windows and Android Release builds are reproducible; final Android identity/signing are settled; no unresolved secret exposure; provider and project licence decisions are documented.

### Phase 1 — Authorized online discovery

Keep local and Internet Archive adapters isolated. Improve Archive music-versus-spoken-word relevance only with provider-supported metadata and regression fixtures; do not fabricate or silently relabel results. Confirm page deltas, errors/rate limits, first-result and complete-page latency, playable URL availability, and startup on real Windows/Android. Decide if result suggestions/history are wanted after reliability and latency targets are measured.

**Exit criteria:** query matrix, multiple-page additions, partial failures, stale requests, relevance and live provider behavior pass on Windows; Android essential search/layout/network behavior passes on a device; latency is recorded; no unauthorized source is enabled.

### Phase 2 — Playback reliability

Capture actionable media_kit/MPV logs; reproduce OSC and cache messages separately for local and online playback. Verify actual sound output, startup latency, buffering, interruption/focus recovery, queue next/previous, retry/skip, URL expiry and background controls on both platforms. Change audio configuration only when reproduced cause and regression coverage support the change.

**Exit criteria:** independent audio-output checks pass; measured search-to-sound and recoverability are within owner-approved targets; Windows and Android playback/queue matrix passes.

### Phase 3 — Download manager and offline listening

The first implementation pass is complete: Discover-to-Downloads flow, permission-gated transfer actions, in-memory task progress/cancel/retry, size validation, managed-file deletion safety, recovery safeguards, and regression tests are in place without changing Sembast/user metadata. Next, perform manual Windows and Android acceptance for eligible/denied items, failed/interrupted transfers, restart, deletion safety, and playback with networking disabled. Consider persistent task state and pause/resume only after platform/source support and recovery behavior are specified; do not bypass `canDownload` or `downloadAllowed`.

**Exit criteria:** allowed download lifecycle survives restart and plays without network; denied/unknown items cannot download; storage recovery, user-visible status and deletion safety are manually confirmed on Windows/Android. Automated checks alone do not satisfy this gate.

### Phase 4 — Updates and release infrastructure

Choose and document one update model. For app-managed updates, use a trusted manifest/signature model, validated packages, explicit installation consent, recovery/rollback and data-preservation tests. For store-managed updates, remove or disable conflicting self-installer behavior. Build CI for analyze/tests, backend tests, Windows/Android artifacts and checksums, but never auto-publish. Verify actual host health and package installation.

**Exit criteria:** signed/reproducible Windows and Android packages; update discovery/verification/installation failure cases pass; release artifact and data migration are verified; CI is green; no unreviewed automatic publication.

### Phase 5 — Product finish and release acceptance

Complete accessibility, permissions, offline status, attribution/licence links, import/export/backup only after storage and service requirements are approved, documentation, privacy disclosures, dependency/security review and device matrix. Complete release checklist with owner decisions and platform-specific tests.

**Exit criteria:** acceptance matrix in the product brief passes; no critical defects remain; source terms and software licence are documented; signed release artifacts and support/recovery procedures are ready. Do not call the product production-ready before this gate.

## Reference project review

The public Musify project describes search suggestions, offline listening, import/export, playlists, radio, lyrics, equalizer, and built-in updates; its public releases include Windows/Linux support notes and versioned release notes. This is product/process inspiration only. The repository identifies GPL-3.0; NM VIBE must not copy its code, assets, branding or integrations. References: [Musify README](https://github.com/gokadzev/Musify), [Musify releases](https://github.com/gokadzev/Musify/releases).
