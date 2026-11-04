# NM VIBE — UI specification

**Version 1.0 · 2026-11-04 · Save as `docs/UI_SPEC.md`**
Read together with `docs/CHATGPT_INSTRUCTIONS.md` (hard rules, layers, report format). If they disagree, stop and ask.

**Status of this document:** it describes the *target* UI. The migrated code already contains most screens, but nobody has audited it against this list. Every item below must be marked **Existing**, **Partial** or **Missing** by an audit before any UI code is changed.

---

## 1. Principles

1. **Smooth first.** No dropped frames in scrolling, transitions, Now Playing or lyrics (see Section 7 of `CHATGPT_INSTRUCTIONS.md`).
2. **Content first.** Album art and track titles lead; chrome stays quiet. No ads, no upsell banners, no tracking prompts.
3. **Every screen has four states:** loading (skeleton), empty (icon + title + hint + action), error (message + Retry), and offline or "not set up" where it applies. A screen must never freeze or show a raw exception.
4. **One look, shared parts.** Anything used by two or more features lives in `lib/shared/widgets/`. No copy-pasted widgets.
5. **Honest licensing in the UI.** Every online track shows its source, credit and licence link. The Download button appears only when the source *and* the track allow it.

---

## 2. Navigation and layout

| Width | Layout |
| --- | --- |
| Under 600 dp (phone) | Bottom `NavigationBar`: **Library, Discover, Playlists, Settings**. Mini player sits just above it. Tapping the mini player opens the full Now Playing page (hero art transition). |
| 600–839 dp (tablet, narrow window) | `NavigationRail` on the left, content on the right, mini player at the bottom. No side pane. |
| 840 dp and up (desktop) | `NavigationRail`, content in the middle, **Now Playing pane** on the right (`desktop_now_playing_pane`). |

- The layout switches by `LayoutBuilder` width, never by platform name, so a resized Windows window behaves like a tablet.
- Back button, Esc (desktop) and the system back gesture all close Now Playing, sheets and detail pages.

---

## 3. Screens

| Screen | Must have | Required states |
| --- | --- | --- |
| **Library** | Tabs: Songs, Albums, Artists, Favorites. Search. Sort. Multi-select bar. Scan status banner. "Add folder" (desktop) / "Scan device" (Android). | Loading skeleton; empty ("Your library starts here" + Add music button); scan running; scan error; **permission denied** (Android media permission) with a button that opens system settings |
| **Album / Artist detail** | Header with art and counts, Play and Shuffle, track list, per-track actions menu | Loading, empty album |
| **Playlists** | List with artwork, create, rename, delete. Detail page with reorder and remove. "Add to playlist" sheet from any track. | Empty ("No playlists yet" + Create) |
| **Discover** | Source chips (Internet Archive, Jamendo), search, result list with **source badge** and **licence badge**, Stream / Download. Credit and licence link on every result. | Initial (suggestions or hint), loading, no results, error + Retry, **offline**, **"Online sources are not set up"** when `BACKEND_URL` is empty (message, not an exception) |
| **Downloads** (NEW) | List grouped by source, size per item, progress, cancel / retry / delete, total storage used | Empty, in progress, failed with Retry, storage low |
| **Now Playing** | Large art, title, artist, seek bar, previous / play-pause / next, shuffle, repeat, queue sheet, synced lyrics view, volume and speed, equalizer entry where supported | Nothing playing, loading track, playback error with Retry/Skip, lyrics missing |
| **Mini player** | Art, title, play/pause, thin progress line | Hidden when the queue is empty |
| **Settings** | Sections: **Appearance** (theme mode, accent colour, dynamic colour on Android), **Library** (folders, rescan), **Playback** (equalizer where supported), **Display** (Refresh rate: Auto (recommended) / Battery saver 60 Hz), **Downloads and cache**, **Updates**, **About** | Each toggle works and persists |
| **About** | App version, "NM VIBE" name and short description, **source credits** (Jamendo credit and link, Internet Archive), open-source licences page | None |
| **Update gate** | Banner or dialog when an update exists; hands off to the store or the verified installer | Checking, up to date, error |
| **First run** | One screen that explains what to do: add a music folder (desktop) or allow media access (Android) | Permission denied |

Sleep timer, Google sign-in / backup, and purchase / unlock screens are **planned and out of scope** for this UI work unless asked.

---

## 4. Design rules

- **Material 3**, light and dark. Colours come from the theme's `ColorScheme`; no hard-coded colours except accent seeds in `core/constants/theme_constants.dart`.
- Android: dynamic colour when available. Accent from album art on Now Playing and the mini player.
- Spacing scale: 4, 8, 12, 16, 24, 32. Card radius 12, sheet radius 28. Minimal elevation.
- Text uses `Theme.of(context).textTheme` only. No fixed font sizes inside widgets.
- Icons: Material icons only. Every icon-only button has a tooltip and a semantic label.
- Repeated pieces (song tile, empty state, skeleton, playlist artwork, collection card) are shared widgets, not rewritten per screen.

---

## 5. Accessibility

- Touch targets at least 48 × 48 dp.
- Text scale up to 200% without overflow or clipped text on any screen.
- Contrast WCAG AA in light and dark.
- `Semantics` labels on seek bar ("Seek, 1 minute 20 of 3 minutes 40"), play/pause, queue items, and badges.
- Desktop keyboard: **Space** play/pause, **←/→** seek 5 s, **Ctrl+F** search, **Esc** back, media keys through `audio_service` where supported. Visible focus rings.

---

## 6. Responsive and theme checks (every screen)

Check at widths **360, 412, 600, 840, 1280** dp, in **light and dark**, at text scale **1.0 and 2.0**. No overflow stripes, no clipped buttons, no layout shift when art loads.

---

## 7. Performance rules for UI code

- `ListView.builder` (or slivers) with `itemExtent` or `prototypeItem` for long lists; test with the 5,000-song list.
- `const` constructors; `RepaintBoundary` around the progress bar and artwork; Riverpod `select` so a position tick never rebuilds a whole page.
- The seek bar listens to the audio position stream and updates **only itself**. No `setState` on a timer.
- Decode artwork at display size (`cacheWidth` / `cacheHeight`), never full size.
- No file, network or database work inside `build()`.
- Motion uses `AnimationController` with a vsync and durations in milliseconds, never frame counts.

---

## 8. Acceptance for any UI task

A UI task is done only when:

- [ ] Each screen touched renders every state in Section 3 (a widget test per state).
- [ ] No overflow at 360 dp and text scale 2.0 (widget test with `MediaQuery` text scaler).
- [ ] Layout switches correctly at 600 and 840 dp (widget test).
- [ ] `flutter analyze` is clean and `flutter test` passes.
- [ ] No new dependency, no new cross-feature import.
- [ ] The report lists what was **not** verified (real phone, 120 Hz, screen reader, high-DPI Windows).

---

## 9. Out of scope

New packages, new music sources, purchase or account screens, translations, store listing assets, and any change to data models or licence rules. If a UI fix needs one of these, stop and ask.
