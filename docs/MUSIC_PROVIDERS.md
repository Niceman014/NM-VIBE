# NM VIBE music source audit

**Checked:** 2026-11-07  
**Scope:** active source registration, live-provider behavior, and retained backend use.

## Active sources

| Source | Status | Capabilities and limitations |
| --- | --- | --- |
| Local files | Active and always available through `LocalFilesMusicSource`. | Searches the scanned library. Local scanning differs by platform. Search indexing is in memory and invalidates when the library changes. |
| Internet Archive | Active and requires no key. | Search, metadata, streaming, and item-permission-gated downloads use `archive.org`. Metadata cache is in memory, keyed by item ID, with no TTL or entry cap. Rights and attribution must be checked for each item; provider metadata is not proof of copyright status. |

Audius and Internet radio are not implemented or approved. No new provider is introduced by this audit.

## Live provider check

A direct request to Internet Archive's advanced-search HTTPS endpoint failed DNS resolution (`No such host is known`) in the verification environment. No live catalog results were received, so current relevance, artist/partial-title behavior, pagination, spoken-word frequency, rate limits, failure behavior, audio URL availability, and playback startup remain unverified. The Windows UI text-entry path was also unavailable in that check.

Official references: [Internet Archive developer portal](https://archive.org/developers/), [Tools and APIs](https://archive.org/developers/index-apis.html), [Item Metadata API](https://archive.org/developers/metadata.html), [rights help](https://help.archive.org/help/rights/). These references do not establish blanket rights for catalog items.

## Search and playback path

`lib/shared/providers/music_providers.dart` registers local files and Internet Archive. `MusicRepository.searchPage` normalizes the query, queries configured sources concurrently, emits each source's ranked page as it completes, preserves partial results on source failures, and removes exact duplicate source IDs. Near-duplicate cross-source recordings are suppressed only when normalized title and artist match and duration is within two seconds, except when metadata indicates distinct versions. Local rows remain distinct.

Local search maintains an in-memory normalized title/artist/album index from `LibraryRepository.watchSongs`, returns 30 rows per page, and caches up to four normalized queries until the library changes. Internet Archive search uses `mediatype:audio` with title/creator terms, returns 20 item IDs per page, then requests item metadata in batches of four. Rows without available metadata are skipped; the request limit is 500 pages. Its identifier-keyed metadata cache has no TTL or size cap.

Ranking orders exact title, exact artist, title prefix/substring, artist prefix, multiword title/artist, album, partial-word, and close typo matches. Fuzzy scores remain below direct text matches and require every query token to be close. Provider-approved rows without title/artist/album matches remain at the bottom because providers may match other metadata fields. Partial provider failures preserve successful results. If all remote providers fail with no results, the UI shows an error; empty results have a separate state.

When playback begins, the active queue snapshots the results visible at that time. Results arriving later do not change queue order. Recording identity remains limited by provider metadata: indistinguishable title, artist, duration, and version metadata cannot be separated reliably.

## Offline downloads

Discover offers saving only when both the registered source and individual track permit it. The download manager serializes transfers, publishes in-memory per-track waiting/downloading/completed/failed/cancelled state and progress, and supports retry/cancel. Completed records and files are stored persistently; active task state is not restored after restart, and pause/resume is unsupported. Existing copies are checked against the published track size when available. The Archive source replaces an unregistered or mismatched final-name file instead of treating it as complete. Deletion removes files only inside the managed download root. Automated tests cover these safeguards; live Archive transfer and offline-device acceptance remain unverified.

## Retained backend

The Node backend now provides `GET /health` and `GET /v1/updates/latest`. It retains CORS policy, per-process rate limiting, update metadata validation, and a short update cache. It no longer mediates music search or stream resolution. Discover queries Internet Archive directly and does not require a backend URL. Deployment state was not verified during this audit.

## Limits and next verification

Internet Archive live behavior and Windows interactive search, scrolling, and playback require an environment with working DNS and a visible app window. Verify relevance, pagination, latency, audio URL availability, startup, and error behavior when those conditions are available. Provider rights and app distribution policy remain item-specific and must be checked before release.
