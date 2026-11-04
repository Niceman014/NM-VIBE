import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/scanner/artwork_service.dart';
import 'package:nm_vibe/data/scanner/scanner_service.dart';
import 'package:nm_vibe/core/scanner/tags/tag_reader.dart';
import 'package:nm_vibe/core/utils/logger.dart';
import 'package:nm_vibe/core/platform/platform_info.dart';

/// Progress and outcome of a library scan, consumed by the library/settings UI.
@immutable
class ScanState {
  const ScanState({
    this.scanning = false,
    this.processed = 0,
    this.total = 0,
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.currentFile,
    this.error,
    this.lastScan,
  });

  final bool scanning;
  final int processed;
  final int total;
  final int added;
  final int updated;
  final int removed;

  /// File currently being read, if a scan is running.
  final String? currentFile;

  /// Last scan error, cleared when a new scan starts.
  final String? error;

  /// When the library was last scanned successfully.
  final DateTime? lastScan;

  bool get hasLibraryChanges => added + updated + removed > 0;

  /// 0.0..1.0; 0.0 while the file list is still being discovered.
  double get progress => total <= 0 ? 0.0 : (processed / total).clamp(0.0, 1.0);

  ScanState copyWith({
    bool? scanning,
    int? processed,
    int? total,
    int? added,
    int? updated,
    int? removed,
    String? currentFile,
    bool clearCurrentFile = false,
    String? error,
    bool clearError = false,
    DateTime? lastScan,
  }) {
    return ScanState(
      scanning: scanning ?? this.scanning,
      processed: processed ?? this.processed,
      total: total ?? this.total,
      added: added ?? this.added,
      updated: updated ?? this.updated,
      removed: removed ?? this.removed,
      currentFile: clearCurrentFile ? null : (currentFile ?? this.currentFile),
      error: clearError ? null : (error ?? this.error),
      lastScan: lastScan ?? this.lastScan,
    );
  }

  @override
  String toString() =>
      'ScanState(scanning: $scanning, $processed/$total, '
      'added: $added, updated: $updated, removed: $removed, error: $error)';
}

/// Drives library scans and folder management.
///
/// Platform detection happens in [_createSource]: Android uses the MediaStore
/// through `on_audio_query`, desktop recursively walks the configured folders.
class ScanController extends StateNotifier<ScanState> {
  ScanController({
    required this._repository,
    ArtworkService? artworkService,
    TagReader? tagReader,
    this._foldersProvider,
    this._addFolderToSettings,
    this._scanSourceFactory,
    this._folderPicker,
  }) : _artworkService = artworkService ?? ArtworkService(),
       _tagReader = tagReader ?? const TagReader(),
       super(const ScanState()) {
    unawaited(_restoreLastScan());
  }

  static const AppLogger _log = AppLogger('ScanController');

  final LibraryRepository _repository;
  final ArtworkService _artworkService;
  final TagReader _tagReader;
  final List<String> Function()? _foldersProvider;
  final Future<void> Function(String folder)? _addFolderToSettings;
  final ScanSource Function(List<String> folders)? _scanSourceFactory;
  final Future<String?> Function()? _folderPicker;

  /// Scans the library. [fullRefresh] also removes songs whose files vanished.
  Future<void> scanLibrary({bool fullRefresh = false}) async {
    if (state.scanning) return;
    final previousLastScan = state.lastScan;
    state = ScanState(scanning: true, lastScan: previousLastScan);
    final stopwatch = Stopwatch()..start();
    try {
      final folders = _foldersProvider?.call() ?? const <String>[];
      final source = _createSource(folders);
      _log.d('Starting ${source.name} (fullRefresh: $fullRefresh)');

      final scanned = await source.scan(onProgress: _reportProgress);
      final result = await applyScanResults(
        _repository,
        scanned,
        fullRefresh: fullRefresh,
      );
      final now = DateTime.now();
      await _repository.setLastScanTime(now);

      if (fullRefresh) {
        final keepKeys = <String>{
          for (final song in result.songs)
            if (song.artworkKey != null && song.artworkKey!.isNotEmpty)
              song.artworkKey!,
        };
        await _artworkService.prune(keepKeys);
      }

      _log.i(
        'Scan done in ${stopwatch.elapsedMilliseconds}ms: '
        '${result.added} added, ${result.updated} updated, '
        '${result.removed} removed',
      );
      if (!mounted) return;
      state = ScanState(
        scanning: false,
        processed: scanned.length,
        total: scanned.length,
        added: result.added,
        updated: result.updated,
        removed: result.removed,
        lastScan: now,
      );
    } catch (error, stackTrace) {
      _log.w('Scan failed', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(
        scanning: false,
        error: _describeError(error),
        clearCurrentFile: true,
      );
    }
  }

  /// Desktop: asks for a folder, persists it and scans. Android: requests the
  /// MediaStore permission and rescans the device library.
  Future<void> addFolder() async {
    if (state.scanning) return;
    try {
      if (PlatformInfo.isMobile) {
        final source = _createSource(const <String>[]);
        if (source is AndroidMediaStoreScanner) {
          final granted = await source.ensurePermission();
          if (!granted) {
            _setError(
              'Storage permission was denied. Allow music access to '
              'scan the device library.',
            );
            return;
          }
        }
        await scanLibrary();
        return;
      }

      final folder = await _pickFolder();
      if (folder == null || folder.trim().isEmpty) return;
      final addToSettings = _addFolderToSettings;
      if (addToSettings != null) await addToSettings(folder.trim());
      await scanLibrary();
    } catch (error, stackTrace) {
      _log.w('Could not add folder', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(error: _describeError(error), scanning: false);
    }
  }

  /// Removes every song from the library and clears the artwork cache.
  Future<void> clearLibrary() async {
    if (state.scanning) return;
    try {
      await _repository.clearSongs();
      await _artworkService.clear();
      if (!mounted) return;
      state = const ScanState();
      _log.i('Library cleared');
    } catch (error, stackTrace) {
      _log.w('Could not clear library', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(error: _describeError(error));
    }
  }

  ScanSource _createSource(List<String> folders) {
    final factory = _scanSourceFactory;
    if (factory != null) return factory(folders);
    if (PlatformInfo.isMobile) {
      return AndroidMediaStoreScanner(artworkService: _artworkService);
    }
    return DesktopFolderScanner(
      artworkService: _artworkService,
      folders: folders,
      tagReader: _tagReader,
    );
  }

  Future<String?> _pickFolder() async {
    final picker = _folderPicker;
    if (picker != null) return picker();
    return FilePicker.getDirectoryPath(dialogTitle: 'Add music folder');
  }

  void _reportProgress(ScanProgress progress) {
    if (!mounted) return;
    state = state.copyWith(
      processed: progress.processed,
      total: progress.total,
      currentFile: progress.currentFile,
      clearCurrentFile: progress.currentFile == null,
    );
  }

  void _setError(String message) {
    if (!mounted) return;
    state = state.copyWith(error: message);
  }

  Future<void> _restoreLastScan() async {
    try {
      final last = await _repository.getLastScanTime();
      if (!mounted || last == null) return;
      state = state.copyWith(lastScan: last);
    } catch (_) {
      // A missing/broken meta record is not user-visible.
    }
  }

  String _describeError(Object error) {
    if (error is ScanPermissionException) return error.message;
    if (error is FileSystemException) return error.message;
    return 'Scan failed: $error';
  }
}

final scanControllerProvider = StateNotifierProvider<ScanController, ScanState>(
  (ref) {
    final repository = ref.watch(libraryRepositoryProvider);
    final settings = ref.read(settingsControllerProvider.notifier);
    final controller = ScanController(
      repository: repository,
      artworkService: ref.watch(artworkServiceProvider),
      foldersProvider: () =>
          ref.read(settingsControllerProvider).libraryFolders,
      addFolderToSettings: (folder) async {
        final folders = List<String>.of(
          ref.read(settingsControllerProvider).libraryFolders,
        );
        final alreadyKnown = folders.any(
          (existing) => existing.toLowerCase() == folder.toLowerCase(),
        );
        if (alreadyKnown) return;
        folders.add(folder);
        await settings.setLibraryFolders(folders);
      },
    );
    return controller;
  },
);
