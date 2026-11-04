# NM VIBE Architecture

- **Layer direction**: features depend on data, and data depends on core.
- **Screen flow**: views call feature controllers, which call repositories.
- **Source boundary**: repositories coordinate music sources and storage in `lib/data/sources/`; Jamendo’s backend adapter also lives there. `music_providers.dart` is shared wiring in `lib/shared/providers/`.
- **Storage boundary**: app storage, database, and settings services belong in `lib/core/storage/`; download file storage belongs in `lib/data/downloads/download_storage.dart`, and its `DownloadRecord` model belongs in `lib/data/models/download_record.dart`.
- **Scanner boundary**: tag parsing and artwork caching belong in `lib/core/scanner/`; the folder and MediaStore scanner belongs in `lib/data/scanner/scanner_service.dart` because it depends on data models and repositories.
- **Platform boundary**: operating-system-specific behavior belongs behind `lib/core/platform/` interfaces.
- **Shared UI**: widgets used by multiple features belong in `lib/shared/widgets/`.
- **Shared navigation and providers**: `lib/shared/navigation/open_now_playing.dart` is the entry point for library and playlist screens to open the player. `lib/shared/providers/` wires repositories and feature controllers. Shared code may import features; features should not import one another.
- **Known feature-import exceptions**: `settings_page.dart` currently imports update, library-scan, and player controllers/services. These four imports are recorded in `docs/DECISIONS.md` for cleanup.
- **Offline playback**: a missing file referenced by a `DownloadRecord` does not fall back to streaming.
- **Migration status**: complete; UI audit and work are next.
