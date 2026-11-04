import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/data/sources/jamendo_service.dart';
import 'package:nm_vibe/data/sources/internet_archive_music_source.dart';
import 'package:nm_vibe/data/sources/jamendo_music_source.dart';
import 'package:nm_vibe/data/sources/local_files_source.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';

final internetArchiveServiceProvider = Provider<InternetArchiveService>((ref) {
  final service = InternetArchiveService(
    wifiOnly: () => ref.read(settingsControllerProvider).wifiOnlyDownloads,
    storageLimitBytes: () =>
        ref.read(settingsControllerProvider).downloadStorageLimitMb * 1024 * 1024,
  );
  ref.onDispose(service.close);
  return service;
});

final musicRepositoryProvider = Provider<MusicRepository>((ref) {
  final service = JamendoService();
  final archiveService = ref.watch(internetArchiveServiceProvider);
  final repository = MusicRepository(
    sources: [
      LocalFilesMusicSource(ref.watch(libraryRepositoryProvider)),
      JamendoMusicSource(service),
      InternetArchiveMusicSource(archiveService),
    ],
  );
  ref.onDispose(repository.close);
  return repository;
});
