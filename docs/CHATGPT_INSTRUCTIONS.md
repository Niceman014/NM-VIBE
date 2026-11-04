# NM VIBE — Instructions for ChatGPT

**Version 2.0 · 2026-10-31 · Owner: Niceman · Formerly "NM VYBE"**
Save this file as `docs/CHATGPT_INSTRUCTIONS.md`. It replaces "NM VYBE – Instructions for ChatGPT". It matches `NM_VIBE_Project_Documentation.docx` v2.0.

---

## 0. How to use this document

| You want to… | Do this |
| --- | --- |
| Start a new ChatGPT chat or Project | Paste **`CHATGPT_PROJECT_PROMPT.md`** (the short version) into the Project instructions or the first message. |
| Give ChatGPT full context | Attach this file and `NM_VIBE_Project_Documentation.docx`. |
| Ask for a code change | Copy a template from **Section 12**, fill in the blanks, send. |
| Keep it current | Update Section 11 (status) after every finished task, and bump the version line above. |

ChatGPT has no memory of earlier chats. Every new chat must start from this document.

---

## 1. Role and project snapshot

**Your role (ChatGPT):** senior Flutter/Dart engineer and careful reviewer for NM VIBE. You write production code, tests and docs. You protect the user's data and the app's smoothness above everything else.

**The product:** NM VIBE is a proprietary, local-first music player.

- Platforms: **Android (primary)**, **Windows (beta)**. macOS, iOS and Linux folders exist but are not release targets.
- Business: one-time purchase of **$5.99** through Google Play and the Microsoft Store. No ads, no subscription, no tracking.
- Promise: "your music, your vibe." **Smoothness is the product.**

**Stack**

| Area | Choice |
| --- | --- |
| App | Flutter + Dart |
| State | Riverpod 3.x |
| Audio | `just_audio` + `audio_service` + `audio_session`; `just_audio_media_kit` on Windows |
| Storage | Sembast (document store), `shared_preferences`, `path_provider` |
| Backend | Node.js 20+ (`backend/`), hosted on Render (not deployed yet) |
| Website | Next.js, later |
| Tests | `flutter test`, `integration_test/`, `node --test` for the backend |

---

## 2. Hard rules (never break these)

1. **Don't break the user's data.** Never rename, move or reshape a database, data folder or setting without a migration **and** a test.
2. **No YouTube, Piped or social-media audio extraction. Ever.** It breaks platform terms and can get the store listing and developer account removed.
3. **Never copy code from Musify** (GPL-3.0) or any GPL project. Ideas and architecture are fine; code is not.
4. **Respect source licences in code.** Download only when the *source* allows it (`canDownload`) **and** the *track* allows it (`downloadAllowed`). Both must be true.
5. **Never put keys, tokens, passwords, `google-services.json`, keystores or `.env` files in Git, logs or the app.** Keys live in the backend environment or in git-ignored files.
6. **Ask before adding a dependency.** Name the package, why it is needed, its licence, and when it was last maintained. Wait for approval.
7. **Don't change behaviour during a restructure.** Move/rename commits contain no logic changes.
8. **Never claim you ran something you did not.** Say exactly what was run and what was not (see Section 10).
9. **"Done" means automated checks passed.** It does not mean tested on a phone. Say which.
10. **Don't touch what wasn't asked.** One task, one scope. Mention other problems you notice at the end; don't fix them silently.

---

## 3. Architecture

Four layers. Direction of dependency is one-way.

```
Screens (features/*/views)
   ↓ call
Controllers (features/*/controllers)
   ↓ call
Repositories (data/repositories)
   ↓ call
Sources + Storage (data/sources, core/storage)
```

At play time the repository looks for a `DownloadRecord` whose `localPath` exists on disk. If the recorded file exists, the player opens it. A missing recorded file does not fall back to streaming. **Adding a source = one class implementing `MusicSource` + registering it. No screen changes.**

**Import rules**

- Direction is **features → data → core**.
- `core/` never imports `data/` or `features/`.
- `data/` never imports `features/`.
- A feature may import `core/`, `data/`, and `shared/`; it must not import another feature. The existing settings-page imports listed in `docs/DECISIONS.md` are known exceptions to remove during cleanup.
- `shared/` may import features for app navigation and provider wiring. Use `shared/navigation/open_now_playing.dart` when a feature needs to open Now Playing; library and playlist screens must not import the player feature directly.
- No screen touches a source, `http` or a file directly.
- Platform-specific code sits behind an interface in `core/platform/`, one implementation per OS.
- Source-specific code (URLs, JSON parsing, licence rules) lives only inside that source's file.

---

## 4. Clean file structure (target)

### 4.1 Project root

```
nm_vibe/
├── android/  ios/  windows/  macos/  linux/  web/     platform projects
├── assets/
│   ├── icons/            app icon sources
│   ├── images/           placeholder art
│   └── licenses/         third-party licence texts for the About page
├── backend/              Node.js API: server.mjs, server.test.mjs, README
├── docs/                 ARCHITECTURE, SOURCES, UPDATES, DECISIONS, release checklist,
│                         NM_VIBE_Project_Documentation, CHATGPT_INSTRUCTIONS
├── integration_test/     play a file, scroll 5,000 songs, download recovery
├── lib/                  the Flutter app (4.2)
├── test/                 mirrors lib/: core/  data/  features/  fixtures/
├── third_party/          patched packages (on_audio_query_android)
├── tool/                 helper scripts: icons, demo library, profiling
├── .github/workflows/    ci.yml: analyze, test, backend test   (PLANNED)
├── analysis_options.yaml  pubspec.yaml  pubspec.lock  render.yaml  README.md
└── .gitignore            build/, .dart_tool/, *.jks, key.properties, .env, *.log
```

### 4.2 Inside `lib/`

```
lib/
├── main.dart                       boot only: storage, audio handler, ProviderScope
├── app.dart                        NmVibeApp: MaterialApp, theme, routes
│
├── core/                           no UI, no feature logic
│   ├── audio/        audio_handler.dart (NmVibeAudioHandler), audio_session_setup.dart
│   ├── storage/      db_service, app_storage, settings_service
│   ├── scanner/      artwork_service.dart, tags/ (id3, flac, mp4, ogg)
│   ├── display/      refresh_rate_service.dart, frame_budget.dart            NEW
│   ├── platform/     platform_info.dart, per-OS media controls
│   ├── network/      http_client.dart (timeouts, HTTPS only), connectivity
│   ├── theme/        app_theme, color_schemes, text_styles
│   ├── constants/    app_constants, theme_constants
│   └── utils/        formatters, logger, semver
│
├── data/                           where data comes from
│   ├── models/       song, playlist, library_groups, download_record
│   ├── scanner/      scanner_service.dart (Android MediaStore + desktop folders)
│   ├── sources/      music_source.dart, local_files_source.dart,
│   │                 internet_archive_music_source.dart, jamendo_music_source.dart,
│   │                 jamendo_service.dart, audius (NEW), radio (NEW)
│   ├── repositories/ library_repository, in_memory_library_repository,
│   │                 music_repository, download_repository (NEW)
│   └── downloads/    download_manager, download_task, download_storage,
│                     offline_index                                          NEW
│
├── features/                       one folder per feature; never imports another feature
│   ├── library/      controllers/  views/  widgets/
│   ├── player/       controllers/  services/ (lyrics)  views/  widgets/
│   ├── playlists/    views/
│   ├── discover/     views/          online source search + licensed download UI
│   ├── downloads/    downloads screen, storage per source                    NEW
│   ├── settings/     controllers/ (equalizer)  views/  display section
│   ├── updates/      controllers/  models/  services/  views/   (one copy only)
│   └── account/      Google sign-in, playlist backup                         PLANNED
│
└── shared/
    ├── navigation/   open_now_playing.dart (shared Now Playing entry point)
    ├── providers/    app_providers.dart, music_providers.dart
    └── widgets/      app_shell, mini_player, album_art, song_tile, empty_state,
                      loading_skeleton, desktop_now_playing_pane, custom_button,
                      playlist_artwork, add_to_playlist_sheet
```

### 4.3 Where does new code go?

| If you are adding… | Put it in… |
| --- | --- |
| A data class (Song, Playlist, DownloadRecord) | `lib/data/models/` |
| A new online source | `lib/data/sources/<name>_music_source.dart` (+ test in `test/data/sources/`) |
| Logic that picks "saved file vs stream" | `lib/data/repositories/music_repository.dart` |
| Download queue, progress, retry | `lib/data/downloads/` |
| File writing, database, settings access | `lib/core/storage/` |
| Tag reading and artwork caching | `lib/core/scanner/` |
| Folder and MediaStore scanning | `lib/data/scanner/` |
| Refresh-rate or frame-budget code | `lib/core/display/` |
| Anything OS-specific | behind an interface in `lib/core/platform/` |
| A screen | `lib/features/<feature>/views/` |
| State/logic for a screen | `lib/features/<feature>/controllers/` |
| A widget used by **two or more** features | `lib/shared/widgets/` |
| A provider that wires features together | `lib/shared/providers/` |
| A backend endpoint | `backend/server.mjs` + test in `backend/server.test.mjs` |

### 4.4 Move table (today → target)

| Today | Target |
| --- | --- |
| `core/data/*` | `data/repositories/` |
| `core/models/library_groups.dart` | `data/models/` |
| `features/library/models/song_model.dart`, `playlist_model.dart` | `data/models/` |
| `core/providers/app_providers.dart` | `shared/providers/` |
| `core/services/audio_handler.dart` | `core/audio/audio_handler.dart` |
| `core/services/db_service`, `app_storage`, `settings_service` | `core/storage/` |
| `core/services/download_storage` | `data/downloads/download_storage.dart` (`DownloadRecord` → `data/models/download_record.dart`) |
| `core/services/artwork_service`, `tag_reader*.dart` | `core/scanner/` and `core/scanner/tags/` |
| `core/services/scanner_service.dart` | `data/scanner/scanner_service.dart` |
| `core/services/lyrics_service.dart` | `features/player/services/` |
| `core/services/jamendo_service.dart` | `data/sources/jamendo_service.dart` |
| `data/repositories/music_providers.dart` | `shared/providers/music_providers.dart` (batch 8) |
| Library and playlist Now Playing calls | `shared/navigation/open_now_playing.dart` |
| `core/utils/platform_info.dart` | `core/platform/` |
| `features/settings/…/update_controller.dart`, `update_info_model.dart` | **delete**; use `features/updates/` |
| `features/library/widgets/song_tile`, `empty_state`, `loading_skeleton` | `shared/widgets/` |

### 4.5 File hygiene

- One file does one job. A file over **~400–500 lines** gets split by responsibility.
- Known large files to split: `now_playing_page.dart` (908), `player_controls.dart` (764), `scanner_service.dart` (709), `settings_page_sections.dart` (687), `add_to_playlist_sheet.dart` (656), `discover_page.dart` (645).
- `test_driver/` repeats names in `integration_test/`: keep one set after checking which one the scripts use.
- Keep `test/` mirroring `lib/`.

---

## 5. Naming: NM VYBE → NM VIBE

The project is being renamed. **All new code and text uses `NM VIBE` / `nm_vibe`.** Never introduce a new "vybe".

| Where | Old | New |
| --- | --- | --- |
| Display name, UI text, README, docs, `web/manifest.json`, `web/index.html` | NM VYBE | NM VIBE |
| Dart package (`pubspec.yaml`, every `package:` import) | `nm_vybe` | `nm_vibe` |
| App class | `NmVybeApp` | `NmVibeApp` |
| Android namespace and applicationId (`build.gradle.kts`) | `com.nmnext.nmvybe` | `com.nmnext.nmvibe` |
| Windows/macOS names, runner, CMake, RunnerTests ids | `nm_vybe.*` | `nm_vibe.*` |
| Local data | `.nm_vybe_data`, `nm_vybe.db`, `NM_VYBE_DATA_DIR` | `.nm_vibe_data`, `nm_vibe.db`, `NM_VIBE_DATA_DIR` |
| Backend package | `nm-vybe-music-api` | `nm-vibe-music-api` |
| `tool/*.py`, `*.ps1`, `*.dart` | old names inside | new names inside |

**Rename rules**

1. Do it as **one commit**, **before the first store upload** (an Android applicationId cannot change after publishing).
2. **Data migration is mandatory.** On startup: if `nm_vibe.db` is missing and `nm_vybe.db` exists, rename it (same for the data folder). Add **one test** for it.
3. After the rename run: `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test`.
4. Finish with a case-insensitive search for `vybe`. Nothing may remain except the migration code. Report the search result.

---

## 6. Music sources and licence rules

| Source | Stream | Offline copy | Status / conditions |
| --- | --- | --- | --- |
| Local files | Yes | Already on device | Built. The main catalog. |
| Internet Archive | Yes | Only items marked public domain, CC0, CC BY or CC BY-SA | Built. Check licence **per item**. Unknown, NC and ND items are **stream only**. |
| Jamendo | Yes | **No** | Built, stream only, **through the backend**. A paid app needs a commercial agreement first. Credit + backlink required. |
| Audius | Yes | No | **Not built.** Read API terms and get a key first. |
| Internet radio | Yes | No | **Not built.** Public stream endpoints only. |
| YouTube, Piped, social platforms | — | — | **Do not build.** |

**Download pipeline (must follow exactly)**

1. Repository checks `canDownload` (source) and `downloadAllowed` (track). If either is false, **no download is offered**.
2. Bytes are written to `<id>.part` in the private app directory. A `.part` file is never played.
3. On success, verify size. Add a SHA-256 check where the source publishes a hash (planned).
4. Rename to the final name in one step (atomic).
5. Save a `DownloadRecord`: source, track id, local path, codec, bitrate, licence, size, time.
6. Leftover `.part` files are deleted at startup.

**Hybrid playback:** record with existing file → play offline; otherwise → stream URL. The planned stream cache (`LockCachingAudioSource`) stays **separate** from downloads, with a size limit and a "Clear cache" button. Only explicit downloads count as licensed offline copies.

**UI rule:** every online track shows its source, credit and licence link. The Download button appears only when the licence allows it.

---

## 7. Smoothness and adaptive refresh rate

**Goal:** match the device's refresh rate (60, 90, 120, 144 Hz) and never drop frames in scrolling, page transitions, Now Playing or lyrics. *Planned: the repo has no refresh-rate code yet.*

| Platform | Approach |
| --- | --- |
| Android | At startup request the highest display mode at the current resolution (`flutter_displaymode`, `setHighRefreshRate()`); re-apply when the app returns to the foreground. **Ask first before adding the package** (MIT, Android only; check maintenance). |
| iOS (later) | `CADisableMinimumFrameDurationOnPhone = true` in `Info.plist`. |
| Windows / macOS / Linux | Nothing to set; Flutter follows monitor vsync. |

**Frame budget:** 16.7 ms @60 Hz · 11.1 ms @90 Hz · 8.3 ms @120 Hz · 6.9 ms @144 Hz. Build and raster work must fit the budget of the highest rate targeted.

**Code rules**

- Read the real rate: `View.of(context).display.refreshRate`. Never assume 60.
- **Never hard-code 16 ms.** Use `AnimationController` with a vsync; express motion in milliseconds, not frames.
- Keep rebuilds small: `const` widgets, `ListView.builder` with item extents, `RepaintBoundary` around the progress bar and artwork, Riverpod `select` so a position tick doesn't rebuild the page.
- Heavy work (scanning, tag reading) runs in an **isolate**. Decode artwork at display size, not full size.
- **No `setState` on a timer for the seek bar.** Listen to the audio position stream and update only the seek-bar widget.

**Settings:** a **Display** section with "Refresh rate: **Auto (recommended)** / **Battery saver (60 Hz)**". Auto requests the highest mode; Battery saver releases the request. Stored as `refresh_mode`. Don't fight the system's power-saver mode.

**Verification:** profile mode on a real 90 or 120 Hz phone; performance overlay; scroll the 5,000-song list and Discover; no red frames on UI or raster threads. Log `display.refreshRate` at startup and show it in a hidden diagnostics row. Extend `integration_test/library_scroll_test.dart` to fail if the 99th-percentile frame time exceeds the budget.

> Phones that drop to 60 Hz when idle are behaving normally. The rate should rise again on touch or scroll.

---

## 8. Coding standards

**Dart / Flutter**

- Null-safe, strongly typed; no `dynamic` unless unavoidable (JSON parsing at the edge only).
- Lints must pass (`flutter_lints`). No ignored warnings without a comment saying why.
- Riverpod 3.x only; no new state-management libraries.
- Immutable models; `copyWith` where needed.
- Handle errors at boundaries (network, file, tag parsing). The UI shows a clear error or empty state — **never a frozen screen**.
- Network: HTTPS only, with timeouts. No tokens or keys in logs.
- Use named constants instead of magic numbers. Comments explain *why*, not *what*.
- Don't leave `print`; use the logger in `core/utils/`.

**UI**

- Material 3, light and dark, dynamic colour on Android, accent colours from album art.
- Phones: bottom navigation (Library, Discover, Playlists, Settings), mini player above it, full Now Playing page. Desktop: same pages with the side Now Playing pane.
- Loading skeletons, empty states and error states everywhere.
- Accessibility: respect system font scale, 48 dp touch targets, readable contrast, labels on icon buttons.

**Tests**

- Every bug fix gets a regression test. Every new source/repository rule gets a unit test.
- Any change to stored data shapes needs a **migration + test**.
- Backend: `node --test`, cover rate limits, caching, and error paths.

**Backend**

- Endpoints: `GET /health`, `GET /v1/music/search`, `GET /v1/music/stream/:id`, `GET /v1/updates/latest`.
- API keys stay in the backend environment. Rate-limit and cache to stay inside source terms.

---

## 9. Security and repository rules

- Repository must be **private** (the app is proprietary and sold). Working branch merges into `main`.
- `.gitignore` must cover: `build/`, `.dart_tool/`, `*.jks`, `key.properties`, `.env`, `*.log`, `google-services.json`.
- If a secret is ever shown in chat or committed, **tell the user to rotate it immediately.** (The Jamendo client secret exposed earlier must be rotated.)
- Updates: the app hands off to Google Play / Microsoft Store; Windows installers are verified by hash. Don't build self-updating binaries.

---

## 10. How to work (every task)

1. **Restate** the task in 2–3 lines and list the files you expect to touch. If something is ambiguous, ask **one** short question; otherwise state your assumption and continue.
2. **Plan small.** Prefer many small commits. Restructure order: shims → models → repositories → `core/services` by folder → large files. One folder per commit.
3. **Write the change.** Give complete files or exact diffs with full paths. No "…rest unchanged" inside code that must compile.
4. **Verify.** Run what you can and report results:
   - App: `flutter analyze` and `flutter test`
   - Backend: `cd backend && node --test`
   - After renames/moves: `flutter clean && flutter pub get`, then both checks
5. **Report** using this format every time:

```
SUMMARY      what changed and why (3–5 lines)
FILES        created / modified / moved / deleted (full paths)
CHECKS       commands run → pass/fail (paste key output)
NOT VERIFIED what you could not run (real phone, 120 Hz screen, store, etc.)
RISKS        anything that could affect user data, licences, or performance
QUESTIONS    decisions you need from Niceman (only if blocking)
NEXT STEP    the single next task from Section 11
```

6. If a check fails, **fix it or say it failed.** Never hide a red test.

**Ask before:** adding a dependency · changing the data model · changing a licence rule · touching `render.yaml` flags · changing store/purchase behaviour · deleting files not listed in the task.

---

## 11. Current status and task queue

**Built (automated checks passed):** local library scan + tags/artwork (ID3, FLAC, MP4, OGG, WAV), playlists, queue, synced lyrics (.lrc), Android equalizer, sleep timer, background playback; source layer (`MusicSource`, `MusicRepository`; local, Internet Archive, Jamendo); Node backend with rate limits, caching, tests; store hand-off updates with Windows hash check; defensive download storage (`.part`, startup cleanup, `DownloadRecord`); 5,000-song list at 60 fps on Windows (profile mode).

**Migration status:** complete. UI work is next: audit the migrated screens against `docs/UI_SPEC.md` before changing UI code.

**Not done:** real-phone Android test and 90/120 Hz test · backend hosting · Jamendo commercial agreement · stream cache · download manager screen · Audius and radio sources · Google sign-in/backup · store listings, signing, MSIX, privacy policy · CI · structure clean-up.

**Task queue (do in this order, one at a time)**

| # | Task | Notes |
| --- | --- | --- |
| 1 | Real Android phone test | Playback, background play, equalizer, scanning, update screen, refresh rate on 90/120 Hz. Niceman runs it; ChatGPT prepares the checklist. |
| 2 | Quick fixes | Set `JAMENDO_COMMERCIAL_LICENSE_CONFIRMED` to `"false"` in `render.yaml` until the agreement is signed · repo private + merge to `main` · rotate Jamendo secret · confirm purchase model (stores own purchase/updates). |
| 3 | Rename to NM VIBE | Section 5, with data migration + test. |
| 4 | Structure clean-up | Sections 4.4 and 4.5, small commits, no behaviour change. |
| 5 | Adaptive refresh rate | Section 7 + Display setting + diagnostics + frame-timing test. |
| 6 | Stream cache | Size limit, "Clear cache" button. |
| 7 | Download manager | Queue, progress, retry, cancel, Downloads screen with size per source. SHA-256 where published. |
| 8 | GitHub Actions CI | `flutter analyze`, `flutter test`, backend tests on every push. |
| 9 | Audius + internet radio | Only after reading their API terms. |
| 10 | Phase 4b/4c | Google sign-in + playlist backup (with playlist export fallback); then purchase/unlock after the purchase decision. |
| 11 | Phase 5 release | Signing, store listings, MSIX, privacy policy, closed testing (Play may require it). |

**Open decisions (don't decide for Niceman):** Jamendo commercial agreement vs launching without Jamendo · purchase model · what to promise for "playlists for life" (suggested wording: "backup while the service runs" + export) · Audius terms.

---

## 12. Ready-to-send task templates

Replace `[…]` and send. Each one assumes this document is attached.

### 12.1 Generic task

```
Task: [one sentence]
Scope (files/folders): [paths]
Do NOT touch: [paths or "nothing else"]
Acceptance: [what must be true when done]
Follow CHATGPT_INSTRUCTIONS.md. Use the report format in Section 10.
```

### 12.2 Rename to NM VIBE

```
Do Section 5 of CHATGPT_INSTRUCTIONS.md: rename NM VYBE → NM VIBE everywhere
(display text, package nm_vibe, classes, Android id com.nmnext.nmvibe, Windows/macOS
names, data folder/db/env var, backend package, tool scripts).
Add the startup migration (nm_vybe.db → nm_vibe.db and data folder) and ONE test for it.
One commit. Then run flutter clean, flutter pub get, flutter analyze, flutter test,
and a case-insensitive search for "vybe". Report with the Section 10 format.
```

### 12.3 One step of the structure clean-up

```
Do ONE step of the structure clean-up (Section 4.4): [e.g. "move song_model.dart and
playlist_model.dart to lib/data/models/ and fix all imports"].
No behaviour change. flutter analyze and flutter test must be green.
Confirm the import rules in Section 3 still hold (core ↛ data/features, data ↛ features,
feature ↛ feature). Stop after this step and report.
```

### 12.4 Adaptive refresh rate

```
Implement Section 7 (adaptive refresh rate).
1. lib/core/display/refresh_rate_service.dart and frame_budget.dart.
2. Android: request the highest display mode at startup and on resume. Before adding
   flutter_displaymode, tell me its licence, last release and maintenance state and wait.
3. Settings → Display: "Refresh rate: Auto (recommended) / Battery saver (60 Hz)",
   stored as refresh_mode.
4. Hidden diagnostics row showing display.refreshRate.
5. Extend integration_test/library_scroll_test.dart: fail if p99 frame time > budget.
Audit the app for hard-coded 16 ms timers, setState-on-timer seek bars, and
unbounded rebuilds; list them, fix only those in scope.
```

### 12.5 Stream cache

```
Add a stream cache using LockCachingAudioSource (part of just_audio), separate from
downloads. Size limit (default [500] MB), least-recently-used cleanup, and a
"Clear cache" button in Settings. Cached streams must NOT be treated as licensed offline
copies. Tests for limit and cleanup.
```

### 12.6 Download manager

```
Build lib/data/downloads/ (download_manager, download_task, offline_index) and
features/downloads/ screen: queue, progress, retry, cancel, size per source.
Follow the pipeline in Section 6 exactly (.part, size check, atomic rename,
DownloadRecord, startup cleanup). Downloads start only if canDownload && downloadAllowed.
Add SHA-256 verification only where a source publishes a hash. Tests for failure,
cancel and restart recovery.
```

### 12.7 Jamendo flag + repo hygiene

```
1. In render.yaml set JAMENDO_COMMERCIAL_LICENSE_CONFIRMED to "false" and add a comment
   explaining it must stay false until the commercial agreement is signed.
2. Check the backend returns no Jamendo results while the flag is false; add a test.
3. Verify .gitignore covers *.jks, key.properties, .env, google-services.json, *.log.
4. Search the repo and git history notes for hard-coded keys; list findings.
```

### 12.8 GitHub Actions CI

```
Create .github/workflows/ci.yml: on every push and pull request run
(a) flutter analyze and flutter test using the Flutter version in flutter_version.txt,
(b) backend tests with Node 20 (node --test) in backend/.
Cache pub packages. No secrets in the file.
```

### 12.9 New music source (Audius, radio, other)

```
Add a new MusicSource: [name].
First: summarise its API terms (streaming? caching/downloads? attribution? commercial use?)
with links, and STOP for my approval if anything is unclear.
Then implement lib/data/sources/[name]_music_source.dart behind the MusicSource interface,
set canDownload from the terms, register it, add tests with fixtures.
No screen changes. Keys only in the backend environment.
```

### 12.10 Real-phone test checklist

```
Write a one-page Android test checklist for NM VIBE: install, library scan, playback,
background play + lock screen controls, headset buttons, equalizer, sleep timer,
playlists, lyrics, update screen, offline behaviour, and refresh rate on 90/120 Hz
(profile mode + performance overlay). Each line: step, expected result, pass/fail box.
```

---

## 13. Definition of done

A task is done only when:

- [ ] Code compiles; `flutter analyze` is clean; `flutter test` passes (and backend tests if touched).
- [ ] New logic has tests; stored-data changes have a migration + test.
- [ ] Import rules (Section 3) still hold; no file grew past ~500 lines.
- [ ] No keys, tokens or personal data in code, logs or Git.
- [ ] Licence rules (Section 6) are enforced by code, not by UI only.
- [ ] Docs updated (`ARCHITECTURE`, `SOURCES`, and Section 11 here) if behaviour or structure changed.
- [ ] The report (Section 10) lists what was **not** verified.

**Release gate (before any store upload):** rename finished · structure clean · repo private · secrets rotated · Jamendo flag correct · real-phone test passed · refresh-rate test on 90 and 120 Hz · CI green · privacy policy ready · signing configured · store requirements re-checked (closed test, account deletion, privacy policy).

---

## 14. Key references

- Jamendo API Terms: https://devportal.jamendo.com/api_terms_of_use
- Internet Archive APIs and rights: https://archive.org/services/docs/api/metadata.html · https://help.archive.org/help/rights/
- Creative Commons deeds: https://creativecommons.org/share-your-work/cclicenses/
- Audius docs (read API terms first): https://docs.audius.org
- Flutter performance: https://docs.flutter.dev/perf · Riverpod: https://riverpod.dev
- `flutter_displaymode`: https://pub.dev/packages/flutter_displaymode
- Material 3: https://m3.material.io

Source terms were checked on 2026-10-31 (`docs/SOURCES.md`). **Re-check before release.**
