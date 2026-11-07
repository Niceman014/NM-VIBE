# NM VIBE implementation status

**Updated:** 2026-11-07

## Current architecture

- Flutter app uses Riverpod, `just_audio`/`audio_service`, Sembast, and a Node backend.
- `MusicRepository` coordinates local files and Internet Archive. Discover searches both directly; it does not require the backend.
- The backend retains health and update metadata endpoints, CORS, rate limiting, metadata validation, and tests.
- User data remains in the existing generic `Song` and `DownloadRecord` formats. Existing records whose source ID is no longer active are retained and are not migrated or deleted.
- Provider adapters and API configuration for the removed catalog have been removed from the app, backend, test fixtures, deployment template, and project documentation. Shared networking, repositories, health, and update functionality remain.

## Recent work

### Phase 1 — Audio state crash stabilization

The confirmed crash was caused by piping `playbackEventStream` into the handler's `BehaviorSubject` with `addStream()` while Repeat/Shuffle code concurrently called `.add()` on the same subject. The handler now listens to player events and publishes with one add path, serializes mode updates, and owns subscription/stream disposal. Error recovery ignores late failures after disposal. Added fake-player injection and regression coverage for competing events, queue changes, mode changes, and disposal.

### Phase 2 — Provider removal and shared service retention

Removed the inactive online catalog adapter and its credential/configuration keys, backend search/stream routes, playback host fallback, Discover configuration warning, obsolete provider test suite, and provider-specific documentation. The backend's `/health` and `/v1/updates/latest` endpoints and their controls remain. No music data schema changed; generic pre-existing source IDs continue to deserialize and remain stored. No credential values were opened or printed. Two matching key/comment lines were removed from the ignored local `backend/.env` without reading or printing values. No deployed host configuration was accessed.

## Verification state before Phase 2 edits

- `flutter analyze`: passed, no issues.
- `flutter test`: passed all 131 tests after Phase 1.
- `git diff --check`: passed (Git emitted line-ending conversion warnings only).
- `flutter build windows --release`: passed; Release executable produced.
- Standard `flutter build apk --debug`: failed while finalizing Kotlin incremental caches.
- Diagnostic serial/nonincremental Gradle Debug build: passed and produced an APK. No project build settings were changed.
- Diagnostic serial/nonincremental Release build: Kotlin stage passed; Android lint failed under installed Java 17 because the lint component attempted `java.util.List.removeLast()`.
- No Android device/emulator was available through ADB. No Android device behavior is claimed.
- Windows Release executable stayed running after launch, but no visible application window was exposed to the computer-use surface. Interactive keyboard, queue, and audio output checks remain unverified.
- Direct Internet Archive search failed DNS resolution (`No such host is known`) during the previous verification. No live relevance, pagination, latency, or provider playback result was obtained.

These checks predate the current Phase 2 code and documentation edits; rerun them before reporting Phase 2 verification.

## Phase 2 and Phase 3 verification

- `flutter analyze`: passed, no issues.
- `flutter test`: passed all 124 remaining tests. Provider-specific adapter tests were removed with that adapter; shared search, Discover, local source, and player regressions pass.
- `node --test` in `backend/`: passed 6/6 health, retired-route, update metadata, rate-limit, and CORS tests.
- `git diff --check`: passed; only CRLF conversion warnings were reported.
- `flutter build windows --release`: passed; produced `build/windows/x64/runner/Release/nm_vibe.exe`.
- Repository-wide text search found no retired-provider names or key names in tracked/untracked project text. Two matching key/comment lines were removed from ignored `backend/.env` without displaying values. Deployment-host variables were not accessed.
- The project background DOCX was updated to remove obsolete provider-specific paragraphs and rows. Its automated renderer could not run because the bundled LibreOffice executable is unavailable; visual layout verification of that DOCX remains incomplete.
- The required `blinding lght` search now ranks “Blinding Lights” above unrelated results. Bounded two-edit tolerance applies only when the query token has at least four characters and the candidate token at least six; the shorter-token threshold remains one edit. The focused ranking/repository tests and all 124 tests pass.

## Search behavior and measured performance

Search normalizes case and whitespace, supports title/artist partial terms, ranks exact text ahead of fuzzy matches, removes exact source-prefixed ID duplicates, and conservatively collapses near-identical cross-source recordings while preserving version variants and local rows. Pages stream into Discover as each source completes, partial failures preserve successful results, and query generations stop stale results from appearing. The queue snapshots visible results when playback starts.

The current synthetic in-memory benchmark at 10,000 records measured a 145 ms first search/index build, 27 ms partial-title search, 36 ms artist search, and 75 µs repeated query. The isolated on-disk Sembast profile at 10,000 records measured 6 ms raw read, 9 ms decode, 10 ms sort, 98 ms search-field normalization, 28 ms repository conversion, 171 ms first search/index build, 27 ms partial-title, 33 ms artist, 52 µs repeated query, and 120 ms from a library update to refreshed search. Earlier Sembast first-search runs were 146–184 ms. The fixture uses the real Sembast schema but generated tracks; it is not the owner's catalog or a phone measurement. Index normalization is the largest measured first-query component, while the complete first search remains under 200 ms in this environment. RSS is not reliable enough to attribute to the index. No additional optimization was justified by the measurements.

The Musify public README was reviewed for product-level ideas including search suggestions, offline listening, import/export, and media UX; its repository is GPL-3.0. No source code or assets were copied. No provider that relies on unauthorized extraction was adopted. The current live Internet Archive attempt could not access the API endpoint; an earlier direct request failed DNS resolution. No current live relevance, latency, pagination, or playable URL finding is claimed.

## Discover-to-offline reliability follow-up

Discover now exposes per-track eligibility reasons and managed download state, progress, retry/cancel, and a route to Downloads. The manager rejects stored downloads with a mismatched size and supports explicit redownload. The Internet Archive source replaces unregistered/mismatched final-name files rather than trusting them. Download deletion removes a file only when its resolved path is inside the managed download root; external files remain untouched. Downloads distinguishes missing files from size mismatches and displays file sizes. Existing offline playback resolution remains covered by repository/player tests.

The Downloads widget test uses deterministic provider states for screen rendering; initial Sembast stream behavior remains covered by a separate storage-backed test. This avoids coupling widget loading to asynchronous filesystem/database work in Flutter's fake-time zone. No user database shape changed. Manager task state is in-memory while completed records persist. Pause/resume and trusted-source hash verification are not implemented.

Latest follow-up checks: `flutter analyze` passed; `flutter test` passed all 142 tests; `flutter build windows --release` passed and produced `build/windows/x64/runner/Release/nm_vibe.exe`; `git diff --check` passed with line-ending conversion warnings. Live Internet Archive transfer, audible output, restart behavior, and playback with networking disabled were not verified. The supplied Windows startup log shows launch and scan only, not offline acceptance.

## Remaining limitations and next phase

- Windows interactive Discover text input and result playback were not verified because no app window was exposed.
- Android device/emulator interaction remains unavailable; standard APK build has a Kotlin incremental-cache issue. Release diagnostics also need a compatible JDK/lint toolchain.
- Internet Archive live search and playback need a working DNS/network environment.
- Backend deployment, update release policy, package identity/signing, software licence, privacy policy, accessibility, source-item attribution, full download/offline acceptance, and owner-device performance remain release gates.
- Next recommended phase: manually verify eligible/denied downloads, recovery, restart, deletion safety, and playback with networking disabled on Windows and Android. Manager task state is currently in-memory; pause/resume is unsupported. Android toolchain, live provider, and DOCX visual checks remain unresolved.
