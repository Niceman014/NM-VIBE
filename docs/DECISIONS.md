# NM VIBE Decisions

- **Product name**: use NM VIBE and `nm_vibe` in new code and text.
- **Source policy**: never build YouTube, Piped, or social-media audio extraction.
- **Jamendo**: keep commercial-license confirmation false until an agreement is signed.
- **Purchase model**: store purchase and entitlement details remain an owner decision.
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
