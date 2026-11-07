# NM VIBE Decisions

- **Product name**: use NM VIBE and `nm_vibe` in new code and text.
- Windows company name changed from com.example to NM Next before the first release; on dev machines the library may need a rescan.
- **Source policy**: never build YouTube, Piped, or social-media audio extraction.
- **Approved product decision**: NM VIBE is a completely free and open-source music player. There will be no paid editions, subscriptions, premium memberships, or paid feature unlocks. The software licence remains a separate owner decision; do not create or replace a root `LICENSE` without approval.
- **Backup promise**: confirm the long-term service promise before building account backup.
- Windows installer filename renamed from `nm_vybe_<version>.exe` to `nm_vibe_<version>.exe`; any leftover old installer in the updates folder is harmless and can be deleted manually.
- `settings_service.dart` and `artwork_service.dart` use Riverpod and Material APIs inside `core/`; this is accepted for the current structure.
- `MusicRepository.close()` and `InternetArchiveService.close()` both close the same Internet Archive service through the source and provider lifecycle.
- A missing downloaded file does not fall back to streaming.
- Discover has no dedicated offline state.
- The old `DownloadStorage.saveRecord` deletes the records file before renaming its replacement.

## Known cross-feature imports, to remove in cleanup

These four settings imports remain as known cross-feature exceptions for cleanup:

- `lib/features/settings/views/settings_page.dart:12` -> `lib/features/updates/controllers/update_controller.dart`.
- `lib/features/settings/views/settings_page.dart:13` -> `lib/features/updates/services/update_strategy.dart`.
- `lib/features/settings/views/settings_page.dart:17` -> `lib/features/library/controllers/scan_controller.dart`.
- `lib/features/settings/views/settings_page.dart:19` -> `lib/features/player/controllers/player_controller.dart`.
