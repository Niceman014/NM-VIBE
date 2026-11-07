import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/data/downloads/download_manager.dart';
import 'package:nm_vibe/data/downloads/download_storage.dart';
import 'package:nm_vibe/data/downloads/offline_index.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/data/sources/internet_archive_music_source.dart';
import 'package:nm_vibe/data/sources/local_files_source.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';

final downloadStorageProvider = Provider<DownloadStorage>(
  (ref) => DownloadStorage(),
);

final internetArchiveServiceProvider = Provider<InternetArchiveService>((ref) {
  final service = InternetArchiveService(
    storage: ref.watch(downloadStorageProvider),
    wifiOnly: () => ref.read(settingsControllerProvider).wifiOnlyDownloads,
    storageLimitBytes: () =>
        ref.read(settingsControllerProvider).downloadStorageLimitMb *
        1024 *
        1024,
  );
  ref.onDispose(service.close);
  return service;
});

final offlineIndexProvider = FutureProvider<List<OfflineTrackEntry>>((ref) {
  return OfflineIndex(ref.watch(downloadStorageProvider)).read();
});

final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  final archiveService = ref.watch(internetArchiveServiceProvider);
  final repository = MusicRepository(
    sources: [
      LocalFilesMusicSource(ref.watch(libraryRepositoryProvider)),
      InternetArchiveMusicSource(archiveService),
    ],
  );
  ref.onDispose(repository.close);
  return repository;
});

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final library = ref.watch(libraryRepositoryProvider);
  final manager = DownloadManager(
    musicRepository: ref.watch(musicRepositoryProvider),
    findSong: library.getSong,
    saveSong: library.updateSong,
  );
  ref.onDispose(() => unawaited(manager.dispose()));
  return manager;
});
