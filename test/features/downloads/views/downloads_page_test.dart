import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/downloads/download_storage.dart';
import 'package:nm_vibe/data/downloads/offline_index.dart';
import 'package:nm_vibe/data/models/download_record.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/features/downloads/views/downloads_page.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/shared/providers/music_providers.dart';
import 'package:nm_vibe/shared/widgets/song_tile.dart';

void main() {
  late Directory root;
  late SembastLibraryRepository library;
  late DownloadStorage storage;
  late File audioFile;
  late Song song;
  late DownloadRecord record;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nm_vibe_downloads_page_');
    library = await SembastLibraryRepository.openInMemory();
    storage = DownloadStorage(
      rootDirectoryOverride: Directory(
        '${root.path}${Platform.pathSeparator}downloads',
      ),
    );
    final sourceDirectory = await storage.sourceDirectory('internet_archive');
    audioFile = File(
      '${sourceDirectory.path}${Platform.pathSeparator}offline.mp3',
    );
    await audioFile.writeAsBytes([1, 2, 3]);
    song = Song(
      id: 'internet_archive:offline',
      filePath: audioFile.path,
      title: 'Offline Song',
      artist: 'Offline Artist',
      album: 'Offline Album',
      albumArtist: 'Offline Artist',
      duration: const Duration(minutes: 2),
      fileSize: 3,
      addedAt: DateTime.utc(2026),
      source: 'internet_archive',
      streamUrl: 'https://archive.org/download/offline/audio.mp3',
      isDownloaded: true,
    );
    await library.saveSongs([song]);
    record = DownloadRecord(
      id: song.id,
      source: 'internet_archive',
      localPath: audioFile.path,
      codec: 'MP3',
      bitrateKbps: 128,
      license: 'CC0',
      downloadedAt: DateTime.utc(2026),
      sizeBytes: 3,
    );
    await storage.saveRecord(record);
  });

  tearDown(() async {
    await library.close();
    await root.delete(recursive: true);
  });

  test('Sembast song stream emits its initial saved records', () async {
    final songs = await library.watchSongs().first.timeout(
      const Duration(seconds: 2),
    );
    expect(songs.single.displayTitle, 'Offline Song');
  });

  testWidgets('shows searchable offline songs and removes one copy safely', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 1440);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _app(
        library,
        _WidgetDownloadStorage(
          rootDirectoryOverride: storage.rootDirectoryOverride!,
          record: record,
        ),
        [song],
        [_entry(record, OfflineFileAvailability.available, 3)],
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('Offline Song'), findsOneWidget);
    expect(find.textContaining('Available offline'), findsOneWidget);
    expect(find.textContaining('3 B'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'artist');
    await _pumpFrames(tester);
    expect(find.text('Offline Song'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove offline copy'));
    await _pumpFrames(tester);
    await tester.tap(find.text('Remove').last);
    await _pumpFrames(tester);

    expect(await tester.runAsync(audioFile.exists), isFalse);
    final updated = await tester.runAsync(() => library.getSong(song.id));
    expect(updated?.isDownloaded, isFalse);
    expect(updated?.filePath, song.streamUrl);
    expect(
      find.textContaining('Removed “Offline Song” offline copy.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a missing-file state without offering playback', (
    tester,
  ) async {
    await tester.runAsync(audioFile.delete);
    await tester.pumpWidget(
      _app(
        library,
        storage,
        [song],
        [_entry(record, OfflineFileAvailability.missing, null)],
      ),
    );
    await _pumpFrames(tester);

    expect(find.textContaining('File missing'), findsOneWidget);
    expect(find.byTooltip('Remove offline copy'), findsOneWidget);
  });

  testWidgets('identifies a size-mismatched file and disables playback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        library,
        storage,
        [song],
        [
          _entry(
            DownloadRecord(
              id: record.id,
              source: record.source,
              localPath: record.localPath,
              codec: record.codec,
              bitrateKbps: record.bitrateKbps,
              license: record.license,
              downloadedAt: record.downloadedAt,
              sizeBytes: 4,
            ),
            OfflineFileAvailability.sizeMismatch,
            3,
          ),
        ],
      ),
    );
    await _pumpFrames(tester);

    expect(find.textContaining('File size mismatch'), findsOneWidget);
    expect(find.textContaining('3 B found, 4 B expected'), findsOneWidget);
    final tile = tester.widget<SongTile>(find.byType(SongTile));
    expect(tile.onTap, isNull);
  });
}

Widget _app(
  SembastLibraryRepository library,
  DownloadStorage storage,
  List<Song> initialSongs,
  List<OfflineTrackEntry> offlineEntries,
) => ProviderScope(
  overrides: [
    libraryRepositoryProvider.overrideWithValue(library),
    songsProvider.overrideWith((ref) => Stream.value(initialSongs)),
    downloadStorageProvider.overrideWithValue(storage),
    offlineIndexProvider.overrideWithValue(AsyncData(offlineEntries)),
  ],
  child: const MaterialApp(home: DownloadsPage()),
);

OfflineTrackEntry _entry(
  DownloadRecord record,
  OfflineFileAvailability availability,
  int? actualSizeBytes,
) => OfflineTrackEntry(
  record: record,
  availability: availability,
  actualSizeBytes: actualSizeBytes,
);

Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

class _WidgetDownloadStorage extends DownloadStorage {
  _WidgetDownloadStorage({
    required super.rootDirectoryOverride,
    required this.record,
  });

  final DownloadRecord record;
  final Set<String> deletedIds = <String>{};

  @override
  Future<DownloadRecord?> deleteRecord(String recordId) async {
    deletedIds.add(recordId);
    if (recordId != record.id) return null;
    final file = File(record.localPath);
    if (file.existsSync()) file.deleteSync();
    return record;
  }
}
