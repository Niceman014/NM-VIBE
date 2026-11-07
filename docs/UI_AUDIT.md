# NM VIBE UI audit

**Scope:** Read-only comparison of `docs/UI_SPEC.md` with `lib/features/` and
`lib/shared/`. Status reflects the code inspected on 2026-11-04. `Existing` means
the described behavior is present; `Partial` means some of it exists or differs
from the spec; `Missing` means no implementation was found. Line references use
repository-relative paths.

## Navigation and layout — UI_SPEC §2

| Spec item | Status | Code evidence |
|---|---|---|
| Phone, under 600 dp: bottom navigation, mini player above it, tap to Now Playing | **Existing** | `lib/shared/widgets/app_shell.dart:98-100, 121-153` selects bottom navigation below 900 dp and includes `MiniPlayer` until the desktop pane breakpoint. `lib/shared/widgets/mini_player.dart:53-65` opens Now Playing on tap. The current threshold also uses the bottom bar at 600–899 dp. |
| Tablet, 600–1179 dp: NavigationRail, content, mini player, no side pane | **Partial** | `app_shell.dart:98-100, 106-153`: widths 600–899 still use bottom navigation; the rail starts at 900 dp. The requested tablet range is now 600–1179 dp. |
| Desktop, 1180 dp and up: rail, content, Now Playing pane | **Existing** | `app_shell.dart:98-100, 106-139` starts the side pane at 1180 dp as specified; widths 900–1179 currently show the rail without the side pane. |
| Layout follows resized window width, not platform | **Partial** | `app_shell.dart:97-100` reads `MediaQuery.sizeOf(context).width`; the behavior is width-based, though it uses `MediaQuery` rather than the spec's `LayoutBuilder`. |
| Back, Esc, system gesture close player, sheets, and details | **Partial** | Player and detail routes use `Navigator` (`lib/features/player/views/now_playing_page.dart:69-103`, `lib/features/library/views/album_detail_page.dart:99-114`, `lib/features/playlists/views/playlist_detail_page.dart:440-449`); Now Playing also supports a vertical-dismiss gesture (`now_playing_page.dart:117-120`). No explicit Esc/keyboard shortcut handler was found. Required-update screen uses `PopScope(canPop: false)` (`lib/features/updates/views/update_gate.dart:52-54`). |

## Screens and states — UI_SPEC §3

### Library

| Requirement/state | Status | Code evidence |
|---|---|---|
| Songs, Albums, Artists tabs; Favorites filter toggle; search, sort, multi-select | **Existing** | Tabs are Songs/Albums/Artists (`lib/features/library/views/library_page.dart:30, 286-306`); Favorites is the filter toggle in `library_page_header.dart:92-95` and `library_page_widgets.dart:132-185`, as decided. Search and sort are in `library_page_header.dart:92-95, 53-73`; multi-select actions are in `lib/features/library/widgets/selection_bar.dart:5-58`. |
| Add folder on desktop / scan device on Android; scan status | **Existing** | Empty state offers scan and desktop folder actions (`lib/features/library/views/library_page_content.dart:108-129`); platform selection and permission request are in `lib/features/library/controllers/scan_controller.dart:168-193`; scan progress/error banner is `lib/features/library/widgets/scan_status_banner.dart:21-120`. |
| Loading skeleton | **Existing** | `library_page_content.dart:21-35`. |
| Empty library | **Existing** | `library_page_content.dart:108-129` uses the accepted copy “Your vibe starts here” / “Scan my music” and provides scan/add-folder actions. |
| Scan running and scan error with Retry | **Existing** | `scan_status_banner.dart:21-33, 65-117`. |
| Android permission denied with action opening system settings | **Partial** | `scan_controller.dart:173-182` records a denied-permission message; `scan_status_banner.dart:73-77` can show Retry. No button to open system settings was found. |

### Album and artist detail

| Requirement/state | Status | Code evidence |
|---|---|---|
| Artwork/header, counts, Play/Shuffle, track list and track actions | **Existing** | Album: `lib/features/library/views/album_detail_page.dart:49-81, 83-145, 165-193`; artist: `lib/features/library/views/artist_detail_page.dart:45-75, 89-165, 180-195`. |
| Loading | **Missing** | The pages receive an `AlbumGroup` or `ArtistGroup` snapshot and build directly (`album_detail_page.dart:22-42`; `artist_detail_page.dart:23-43`); no loading branch is present. |
| Empty album/artist | **Existing** | `album_detail_page.dart:151-159`; `artist_detail_page.dart:166-174`. |
| Error state | **Missing** | No page-level error branch was found; these views render the supplied group snapshot. |

### Playlists

| Requirement/state | Status | Code evidence |
|---|---|---|
| List artwork, create, rename, delete; detail reorder/remove; add-to-playlist sheet | **Existing** | List and create: `lib/features/playlists/views/playlists_page.dart:90-108`; rename/delete handlers: `playlists_page.dart:212-274`; detail reorder/remove handlers: `lib/features/playlists/views/playlist_detail_page.dart:361-365, 438-501`; shared add sheet: `lib/shared/widgets/add_to_playlist_sheet.dart:88-155`. |
| List loading | **Existing** | Skeleton branch: `playlists_page.dart:128-139`. |
| List error with retry | **Existing** | `playlists_page.dart:114-127`. |
| List empty with create | **Existing** | `playlists_page.dart:140-154`. |
| Detail loading | **Existing** | Spinner while the target playlist is unresolved: `playlist_detail_page.dart:46-58`. |
| Detail empty playlist | **Existing** | Blank-playlist message and Add songs action: `playlist_detail_page.dart:134-148`. |
| Detail error | **Missing** | Stream error is not rendered distinctly; missing value falls through to “Playlist not found” (`playlist_detail_page.dart:46-67`). |

### Discover

| Requirement/state | Status | Code evidence |
|---|---|---|
| Active source selection chips | **Missing** | The screen builds a heading and search field (`lib/features/discover/views/discover_page.dart:222-265`); no source selector was found. |
| Source badge and decision-defined licence badge on each result | **Partial** | The tile displays creator/source attribution text (`discover_page.dart:352-357, 459-466`), but no separate source or licence badge was found. The licence link is conditional on `track.licenseUrl` (`discover_page.dart:361-363, 482-489`). |
| Stream, download, creator credit, item/licence links and unknown-licence label | **Partial** | Play and download actions are wired at `discover_page.dart:352-368`; credit and links are in `discover_page.dart:459-489`. Unknown items do not yet display the decided “Licence unknown, stream only” badge. |
| Initial suggestions or hint | **Partial** | Configured sources auto-search an empty query (`discover_page.dart:33-38`); heading/search field at `243-264`, but no curated suggestions. |
| Loading | **Existing** | Skeleton: `discover_page.dart:316-324`. |
| No results | **Existing** | “No tracks found” state: `discover_page.dart:325-331`. |
| Error with Retry | **Existing** | The error branch keeps Retry (`discover_page.dart:315-318`); categorized messages are produced by `discover_error_message.dart:14-23` and logged with the original exception at `discover_page.dart:68-73`. |
| Offline connection message | **Existing** | `discover_error_message.dart:18-21` maps socket, timeout and HTTP client failures to the offline message in the shared Discover error branch (`discover_page.dart:315-318`). |
| Search source availability | **Existing** | The setup notice is shown when no search source is configured (`discover_page.dart`). |

### Downloads

| Requirement/state | Status | Code evidence |
|---|---|---|
| Downloads screen and source grouping | **Missing** | No Dart screen/controller implementation exists under `lib/features/downloads/`. |
| Per-item size, progress, cancel, retry, delete, total usage | **Missing** | Settings has a total size and delete control for Internet Archive offline copies (`lib/features/settings/views/settings_page_sections.dart:4-64`), not the manager controls. |
| Empty state | **Missing** | No Downloads screen exists. |
| In-progress state | **Missing** | No Downloads screen exists. |
| Failed with Retry | **Missing** | No Downloads screen exists. |
| Storage-low state | **Missing** | No Downloads screen exists. |

### Now Playing

| Requirement/state | Status | Code evidence |
|---|---|---|
| Art, title/artist, seek, transport, shuffle/repeat, queue, lyrics, volume/speed, equalizer | **Partial** | Main player and responsive layouts: `lib/features/player/views/now_playing_page.dart:117-148, 368-520`; transport: `lib/features/player/views/player_controls.dart:202-270`; secondary actions: `player_controls.dart:434-523`. Volume is not shown in the Now Playing action row; speed, lyrics, queue, sleep timer, and supported equalizer are. |
| Nothing playing | **Existing** | `now_playing_page.dart:746-830`. |
| Loading track | **Partial** | `player_controls.dart:213-225, 347-390` observes loading and disables/shows progress in controls; no dedicated whole-screen loading state was found. |
| Playback error with Retry/Skip | **Partial** | Error banner displays the message (`now_playing_page.dart:315-363`), but it has no Retry or Skip action. |
| Lyrics missing | **Existing** | `lib/features/player/views/lyrics_view.dart:107-129`. Lyrics loading/error are also handled at `lyrics_view.dart:97-106`. |

### Mini player

| Requirement/state | Status | Code evidence |
|---|---|---|
| Artwork, title, play/pause, progress; tap opens Now Playing | **Existing** | `lib/shared/widgets/mini_player.dart:53-79, 87-125, 183-222`. |
| Hidden when queue is empty | **Partial** | It hides when there is no current song (`mini_player.dart:19-25`), not by directly checking queue emptiness. |

### Settings

| Requirement/state | Status | Code evidence |
|---|---|---|
| Appearance, library, playback, downloads, updates, about | **Existing** | Section assembly: `lib/features/settings/views/settings_page.dart:385-417`; appearance/library/playback: `lib/features/settings/views/settings_page_sections.dart:80-181, 204-320, 354-445`; downloads: `settings_page_sections.dart:4-64`; updates/about: `settings_page_sections.dart:449-640`. |
| Display refresh-rate setting | **Missing** | No Display section or refresh-rate control appears in the section assembly (`settings_page.dart:385-417`) or settings sections. |
| Downloads and cache controls | **Partial** | Offline-download Wi-Fi/storage/delete settings exist (`settings_page_sections.dart:4-64`); no stream-cache controls were found. |
| Every setting persists | **Partial** | Settings bind to `SettingsController` setters (for example `settings_page_sections.dart:98-180, 307-312`); persistence was not verified by this source-only audit. |

### About

| Requirement/state | Status | Code evidence |
|---|---|---|
| Version, app name and description/tagline | **Existing** | `lib/features/settings/views/settings_page_sections.dart:449-518`. |
| Online source credits and links | **Missing** | About shows app identity/tagline and general licence page (`settings_page_sections.dart:499-518, 628-639`); no source credits or source links were found there. |
| Open-source licence page | **Existing** | `settings_page_sections.dart:628-639`. About is a Settings section, not a separate screen. |

### Update gate

| Requirement/state | Status | Code evidence |
|---|---|---|
| Automatic update check and required-update gate | **Existing** | Automatic check: `lib/features/updates/views/update_gate.dart:18-37`; required-update screen: `update_gate.dart:40-160`. |
| Checking | **Partial** | Required-update view shows a progress indicator at `update_gate.dart:141-143`; otherwise the gate displays its child (`update_gate.dart:31-37`). |
| Error with Retry | **Existing** | `update_gate.dart:102-139`. |
| Downloading and verifying | **Existing** | `update_gate.dart:85-101`. |
| Up-to-date status location | **Existing** | The decision is to show this status in Settings only; text is at `lib/features/settings/views/settings_page_sections.dart:671-685`. The gate returns its child when no update is required (`update_gate.dart:31-37`). |

### First run

| Requirement/state | Status | Code evidence |
|---|---|---|
| First-run guidance via Library empty state; no separate screen | **Existing** | The accepted design uses the Library empty state for first-use guidance and has no separate onboarding page (`lib/features/library/views/library_page_content.dart:108-129`). |
| Android permission denied guidance | **Partial** | Denial message exists (`lib/features/library/controllers/scan_controller.dart:173-182`); there is no system-settings action. |

## Gaps by priority

### P0 — correct navigation behavior and unblock core use

1. Add the missing Download manager screen and its required queue/progress/recovery states, or revise the UI spec if it is intentionally deferred. Current feature folder has no Dart screen.
2. Align app-shell breakpoints with the target phone/tablet/desktop ranges. Current thresholds are 900 dp for rail and 1180 dp for the side pane (`lib/shared/widgets/app_shell.dart:98-100`).

### P1 — states and source clarity

4. Add an explicit Android permission-denied recovery action that opens system settings; current scan error only offers retry (`lib/features/library/controllers/scan_controller.dart:173-182`; `lib/features/library/widgets/scan_status_banner.dart:73-77`).
5. Add Discover's decided source chips and visible source/licence badges; none are currently rendered as selectors/badges (`lib/features/discover/views/discover_page.dart:222-265, 459-489`).
6. Show the decided “Licence unknown, stream only” badge when `licenseUrl` is null; do not add a link for unknown licences (`discover_page.dart:361-363`).
7. Add Retry/Skip actions to playback errors if the spec remains binding (`lib/features/player/views/now_playing_page.dart:315-363`).
8. Add the settings Display section and About source credits/links (`settings_page.dart:385-417`; `settings_page_sections.dart:449-518`).
9. Make empty detail data, stream errors, and update status handling explicit where the spec calls for those states (`album_detail_page.dart:39-42`; `playlist_detail_page.dart:46-67`; `update_gate.dart:31-37`).

### P2 — spec and polish

10. Verify narrow layouts and text scaling at the spec's full matrix before changing fixed sizing.

## States absent or not dedicated

- **No dedicated screen-level loading/empty/error/offline states:** About, Settings, and the mini player; their data subcomponents have some local progress/error handling, but the screens themselves do not implement all four generic states.
- **No loading/error states:** album and artist details; they render supplied group snapshots and an empty state only (`album_detail_page.dart:22-42, 151-159`; `artist_detail_page.dart:23-43, 166-174`).
- **Discover offline:** Existing as a categorized connection message in the error state, not as a separate screen or live connectivity monitor (`discover_error_message.dart:18-21`; `discover_page.dart:315-318`).
- **No Downloads screen or any of its required states:** `lib/features/downloads/` has no Dart implementation.
- **No separate First-run screen by decision:** first-use guidance belongs in the Library empty state (`library_page_content.dart:108-129`).
- **Update gate has no up-to-date state of its own by design:** the status belongs in Settings (`update_gate.dart:31-37`; `settings_page_sections.dart:671-685`).
- **Playback error has no retry/skip control:** the player error banner only displays text (`now_playing_page.dart:315-363`).

## Hard-coded colours and sizes

- No literal `Color(0x...)`, `Color.fromARGB`, or `Color.fromRGBO` was found in `lib/features/` or `lib/shared/`; most screen colour choices use the theme `ColorScheme`.
- Direct palette exceptions include `Colors.black` overlay in `lib/shared/widgets/album_art.dart:321`, `Colors.white`/`Colors.black87` in `lib/features/player/controllers/palette_controller.dart:64-65`, and transparent surfaces in library, playlist, settings, and shared widgets.
- Fixed title font sizes override theme type sizes: album `44` at `lib/features/library/views/album_detail_page.dart:310`; artist `44` at `artist_detail_page.dart:278`; playlist `40` at `lib/features/playlists/views/playlist_detail_page.dart:273`; lyrics use current-line/non-current-line `22`/`16` values at `lib/features/player/views/lyrics_view.dart:286-288`. Flutter's text scaler still applies, so these need 2.0-scale layout checks.
- Fixed geometry is widespread and mostly intentional for icons/art/skeletons. Notable responsive-risk values include the 64 dp desktop player gap (`now_playing_page.dart:493`), 44 dp mini-player artwork (`lib/shared/widgets/mini_player.dart:87-97`), 900/1180 dp shell thresholds (`app_shell.dart:98-100`), and the fixed library-header controls on one row (`library_page_header.dart:33-74`).

## Duplicated or parallel widget implementations

- Discover's private `_MessageState` repeats the centered icon/title/message/action pattern already supplied by shared `EmptyState` (`lib/features/discover/views/discover_page.dart:587-640`; `lib/shared/widgets/empty_state.dart:7-88`).
- Album/artist collage cards and shared `PlaylistArtwork` each compose album art into collection artwork (`lib/features/library/widgets/collection_cards.dart:9-110`; `lib/shared/widgets/playlist_artwork.dart:8-90`). They serve different data contexts but are candidates for a shared artwork primitive.
- The desktop Now Playing pane and full player each implement previous/play/next controls (`lib/shared/widgets/desktop_now_playing_pane.dart:179-219`; `lib/features/player/views/player_controls.dart:202-270`). This may be intentional responsive presentation, but control behavior should remain consistent.
- The repo has reusable `EmptyState` and `SkeletonSongList` (`lib/shared/widgets/empty_state.dart:7-88`; `loading_skeleton.dart:6-22`), but several screens implement their own message/empty presentation (Discover, lyrics, queue, update gate).

## Likely 360 dp / 2.0 text-scale overflow risks

- **Fixed in the Library narrow-header task:** below 440 dp the brand label stacks above the actions, and the Favourites filter becomes a labeled compact icon. Widget coverage checks widths 254, 360 and 600 dp at text scales 1.0 and 2.0.
- **High risk:** settings content at 360 dp / 2.0 scale, particularly segmented theme buttons and dense `ListTile` rows (`lib/features/settings/views/settings_page_sections.dart:98-120, 204-320, 354-445`). Settings screen has a 900 dp wide-layout split (`lib/features/settings/views/settings_page.dart:370-417`).
- **High risk:** long album/artist names use fixed 44 dp titles and playlist titles use 40 dp (`album_detail_page.dart:310`; `artist_detail_page.dart:278`; `playlist_detail_page.dart:273`); their hero rows and actions should be checked at 360 dp and 2.0 scale.
- **Medium risk:** Discover result rows have 54 dp art plus multiple metadata/credit/link lines and action buttons (`lib/features/discover/views/discover_page.dart:407-429, 459-539`).
- **Medium risk:** Now Playing uses a minimum 140 dp artwork clamp and fixed horizontal padding at narrow widths (`lib/features/player/views/now_playing_page.dart:407-425`); this is scrollable, but should be tested with 2.0 text scale.
- Remaining entries are source-based risk candidates; the known library-header case now has a viewport/text-scale widget test.

## Spec items to reconsider

- UI_SPEC §2 now sets breakpoints at 600/1180 dp; the shell still uses 900/1180 dp (`app_shell.dart:98-100`).
- Discover source chips and licence labels are now decided; the code still lacks selectors and visible badges (`discover_page.dart:222-265, 459-489`).
- Unknown licence means “Licence unknown, stream only” with no link; the view still omits the licence link without displaying that badge (`discover_page.dart:361-363`).
- The spec describes Downloads as a screen, but current settings only expose offline-download controls; the dedicated feature is absent.
- The spec calls for a Display setting, but the settings page currently has no Display section.
- Each screen implements its listed states; no universal four-state rule applies to components such as the mini player and About section.

## Proposed work order (one screen per task)

Sizes are rough effort estimates, not file line counts; each item should be a separate reviewable UI task.

1. **Library narrow header** — Complete (responsive at narrow widths; tested at 254, 360 and 600 dp with text scales 1.0 and 2.0).
2. **App-shell navigation breakpoints** — M (bottom bar below 600 dp, rail from 600 dp, pane from 1180 dp).
3. **Library permission-denied recovery** — S (clear explanation plus system-settings action).
4. **Album detail** — M (empty/loading/error behavior and 360 dp/2.0 scale checks).
5. **Artist detail** — M (same responsive/state audit as album detail).
6. **Playlist list and detail** — M (detail error handling and responsive text/layout checks).
7. **Discover** — L (source selection/badges, unknown-licence label, responsive results).
8. **Downloads screen** — L (screen and required queue, progress, failure, empty, storage states).
9. **Now Playing and lyrics** — L (playback recovery actions, scale/responsive checks, verify control consistency).
10. **Settings** — M (Display section decision, narrow rows and 2.0 text scale).
11. **About section** — S (source credits and links).
12. **Update gate** — S (keep the up-to-date status in Settings only; verify the existing status).
