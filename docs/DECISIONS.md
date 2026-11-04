# NM VIBE Decisions

- **Product name**: use NM VIBE and `nm_vibe` in new code and text.
- **Source policy**: never build YouTube, Piped, or social-media audio extraction.
- **Jamendo**: keep commercial-license confirmation false until an agreement is signed.
- **Purchase model**: store purchase and entitlement details remain an owner decision.
- **Backup promise**: confirm the long-term service promise before building account backup.
- Windows installer filename renamed from `nm_vybe_<version>.exe` to `nm_vibe_<version>.exe`; any leftover old installer in the updates folder is harmless and can be deleted manually.

## Known cross-feature imports, to remove in cleanup

These settings imports remain in the old ZIP sources and will be handled in the settings batch:

- `lib/features/settings/views/settings_page.dart:12` -> `lib/features/updates/controllers/update_controller.dart`.
- `lib/features/settings/views/settings_page.dart:13` -> `lib/features/updates/services/update_strategy.dart`.
- `lib/features/settings/views/settings_page.dart:17` -> `lib/features/library/controllers/scan_controller.dart`.
- `lib/features/settings/views/settings_page.dart:19` -> `lib/features/player/controllers/player_controller.dart`.
