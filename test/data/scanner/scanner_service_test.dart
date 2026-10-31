import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/core/scanner/artwork_service.dart';
import 'package:nm_vibe/data/scanner/scanner_service.dart';
import 'package:nm_vibe/data/models/song_model.dart';

void main() {
  group('parseFilenameTags', () {
    test('reads track number, artist and title', () {
      final tags = parseFilenameTags('03. Nova Kane - Afterglow Drive');
      expect(tags.artist, 'Nova Kane');
      expect(tags.title, 'Afterglow Drive');
      expect(tags.trackNumber, 3);
    });

    test('keeps a plain filename as the title', () {
      final tags = parseFilenameTags('Night Bloom');
      expect(tags.title, 'Night Bloom');
      expect(tags.artist, isNull);
      expect(tags.trackNumber, isNull);
    });
  });

  test(
    'desktop scan walks asynchronously, ignores hidden folders and dedupes',
    () async {
      final root = await Directory.systemTemp.createTemp('nm_vibe_scan_');
      addTearDown(() => root.delete(recursive: true));

      final album = Directory('${root.path}${Platform.pathSeparator}Album');
      final hidden = Directory('${root.path}${Platform.pathSeparator}.cache');
      await album.create(recursive: true);
      await hidden.create(recursive: true);
      await File(
        '${album.path}${Platform.pathSeparator}01 Nova Kane - Dawn.mp3',
      ).writeAsString('not real audio; filename fallback is expected');
      await File('${hidden.path}${Platform.pathSeparator}Hidden.mp3')
          .writeAsString('ignored');
      await File('${root.path}${Platform.pathSeparator}readme.txt')
          .writeAsString('ignored');

      final progress = <ScanProgress>[];
      final songs = await DesktopFolderScanner(
        artworkService: ArtworkService(),
        folders: <String>[root.path, root.path],
      ).scan(onProgress: progress.add);

      expect(songs, hasLength(1));
      expect(songs.single.title, 'Dawn');
      expect(songs.single.artist, 'Nova Kane');
      expect(songs.single.trackNumber, 1);
      expect(progress.any((item) => item.total == 0), isTrue);
      expect(progress.last.processed, 1);
      expect(progress.last.total, 1);
    },
  );

  test('full refresh keeps existing offline downloads', () async {
    final root = await Directory.systemTemp.createTemp('nm_vibe_download_');
    addTearDown(() => root.delete(recursive: true));
    final downloadedFile = File(
      '${root.path}${Platform.pathSeparator}track.mp3',
    );
    await downloadedFile.writeAsString('downloaded audio');

    final repository = await SembastLibraryRepository.openInMemory();
    addTearDown(repository.close);
    final downloaded = Song(
      id: 'jamendo:123',
      filePath: downloadedFile.path,
      title: 'Offline track',
      artist: 'Artist',
      album: 'Album',
      albumArtist: 'Artist',
      duration: const Duration(minutes: 2),
      fileSize: await downloadedFile.length(),
      addedAt: DateTime.now(),
      source: 'jamendo',
      streamUrl: 'https://prod-1.storage.jamendo.com/?trackid=123',
      isDownloaded: true,
    );
    await repository.saveSongs(<Song>[downloaded]);

    final result = await applyScanResults(
      repository,
      const <Song>[],
      fullRefresh: true,
    );

    expect(result.songs, hasLength(1));
    expect(result.songs.single.id, downloaded.id);
    expect(await repository.getSongs(), hasLength(1));
  });
}
