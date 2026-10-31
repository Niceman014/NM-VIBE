# NM VIBE Architecture

- **Layer direction**: features depend on data, and data depends on core.
- **Screen flow**: views call feature controllers, which call repositories.
- **Source boundary**: repositories coordinate music sources and storage in `lib/data/sources/`; Jamendo’s backend adapter also lives there. `music_providers.dart` is shared wiring in `lib/shared/providers/`.
- **Storage boundary**: app storage, database, and settings services belong in `lib/core/storage/`; download file storage belongs in `lib/data/downloads/download_storage.dart`, and its `DownloadRecord` model belongs in `lib/data/models/download_record.dart`.
- **Scanner boundary**: tag parsing and artwork caching belong in `lib/core/scanner/`; the folder and MediaStore scanner belongs in `lib/data/scanner/scanner_service.dart` because it depends on data models and repositories.
- **Platform boundary**: operating-system-specific behavior belongs behind `lib/core/platform/` interfaces.
- **Shared UI**: widgets used by multiple features belong in `lib/shared/widgets/`.
