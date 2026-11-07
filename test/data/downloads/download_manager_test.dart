import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/downloads/download_manager.dart';
import 'package:nm_vibe/data/downloads/download_task.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/sources/music_source.dart';

void main() {
  late Directory root;
  late _FakeSource source;
  late Map<String, Song> library;
  late List<Song> saved;
  late DownloadManager manager;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nm_vibe_download_manager_');
    source = _FakeSource();
    library = <String, Song>{};
    saved = <Song>[];
    manager = DownloadManager(
      musicRepository: MusicRepository(sources: [source]),
      findSong: (id) async => library[id],
      saveSong: (song) async {
        library[song.id] = song;
        saved.add(song);
      },
    );
  });

  tearDown(() async {
    await manager.dispose();
    await root.delete(recursive: true);
  });

  test('rejects downloads without both source and track permission', () async {
    final track = _Track('denied', downloadAllowed: false);

    await expectLater(manager.enqueue(track), throwsStateError);
    source.downloadEnabled = false;
    await expectLater(
      manager.enqueue(_Track('source-denied')),
      throwsStateError,
    );
    expect(source.started, 0);
  });

  test(
    'deduplicates jobs and persists only a verified completed file',
    () async {
      final track = _Track('complete');
      final file = await _audioFile(root, 'complete.mp3', [1, 2, 3]);
      source.onStart = (track, onProgress) {
        onProgress(3, 3);
        return DownloadTask(Future<File>.value(file), () async {});
      };

      final first = await manager.enqueue(track);
      final duplicate = await manager.enqueue(track);
      final completedFile = await first.result;

      expect(duplicate, same(first));
      expect(completedFile.path, file.path);
      expect(source.started, 1);
      expect(saved.single.isDownloaded, isTrue);
      expect(saved.single.filePath, file.path);
      expect(manager.task(first.id)?.status, ManagedDownloadStatus.completed);
      expect(manager.task(first.id)?.progress, 1);
    },
  );

  test(
    'allows a new transfer if a previously completed file was removed',
    () async {
      final track = _Track('redownload');
      final original = await _audioFile(root, 'original.mp3', [1, 2]);
      final replacement = await _audioFile(root, 'replacement.mp3', [3, 4]);
      source.onStart = (track, onProgress) => DownloadTask(
        Future<File>.value(source.started == 1 ? original : replacement),
        () async {},
      );

      final first = await manager.enqueue(track);
      await first.result;
      await original.delete();

      final next = await manager.enqueue(track);
      await next.result;

      expect(source.started, 2);
      expect(manager.task(next.id)?.file?.path, replacement.path);
    },
  );

  test('does not treat a size-mismatched saved song as complete', () async {
    final track = _Track('mismatched');
    final damaged = await _audioFile(root, 'damaged.mp3', [1, 2, 3]);
    final replacement = await _audioFile(root, 'replacement.mp3', [4, 5, 6, 7]);
    library[track.toSong().id] = track.toSong().copyWith(
      filePath: damaged.path,
      fileSize: 2,
      isDownloaded: true,
    );
    source.onStart = (track, onProgress) =>
        DownloadTask(Future<File>.value(replacement), () async {});

    final job = await manager.enqueue(track);
    await job.result;

    expect(source.started, 1);
    expect(manager.task(job.id)?.file?.path, replacement.path);
    expect(library[track.toSong().id]?.fileSize, 4);
  });

  test(
    'redownload forces a fresh transfer for an invalid saved copy',
    () async {
      final track = _Track('repair');
      final previous = await _audioFile(root, 'previous.mp3', [1, 2, 3]);
      final replacement = await _audioFile(root, 'repaired.mp3', [4, 5]);
      library[track.toSong().id] = track.toSong().copyWith(
        filePath: previous.path,
        fileSize: 3,
        isDownloaded: true,
      );
      source.onStart = (track, onProgress) =>
          DownloadTask(Future<File>.value(replacement), () async {});

      final job = await manager.redownload(track);
      await job.result;

      expect(source.started, 1);
      expect(library[track.toSong().id]?.filePath, replacement.path);
      expect(library[track.toSong().id]?.isDownloaded, isTrue);
    },
  );

  test('limits concurrency and cancels a waiting job', () async {
    final firstTrack = _Track('active');
    final queuedTrack = _Track('queued');
    final activeFile = await _audioFile(root, 'active.mp3', [1, 2]);
    final transfer = Completer<File>();
    source.onStart = (track, onProgress) =>
        DownloadTask(transfer.future, () async {
          if (!transfer.isCompleted) {
            transfer.completeError(const DownloadCancelled());
          }
        });

    final active = await manager.enqueue(firstTrack);
    final queued = await manager.enqueue(queuedTrack);
    await Future<void>.delayed(Duration.zero);
    expect(source.started, 1);
    expect(manager.task(queued.id)?.status, ManagedDownloadStatus.waiting);

    await queued.cancel();
    await expectLater(queued.result, throwsA(isA<DownloadCancelled>()));
    transfer.complete(activeFile);
    await active.result;

    expect(manager.task(queued.id)?.status, ManagedDownloadStatus.cancelled);
    expect(saved.map((song) => song.id), [firstTrack.toSong().id]);
  });

  test('cancels an active transfer and removes its partial output', () async {
    final track = _Track('cancel-active');
    final transfer = Completer<File>();
    var cancelCalled = false;
    source.onStart = (track, onProgress) =>
        DownloadTask(transfer.future, () async {
          cancelCalled = true;
          if (!transfer.isCompleted) {
            transfer.completeError(const DownloadCancelled());
          }
        });

    final job = await manager.enqueue(track);
    await Future<void>.delayed(Duration.zero);
    await job.cancel();
    await expectLater(job.result, throwsA(isA<DownloadCancelled>()));

    expect(cancelCalled, isTrue);
    expect(manager.task(job.id)?.status, ManagedDownloadStatus.cancelled);
    expect(saved, isEmpty);
  });

  test(
    'failed jobs can retry and empty output is never marked downloaded',
    () async {
      final track = _Track('retry');
      var attempts = 0;
      final file = await _audioFile(root, 'retry.mp3', const <int>[]);
      source.onStart = (track, onProgress) {
        attempts++;
        if (attempts == 1) {
          return DownloadTask(
            Future<File>.error(StateError('network interrupted')),
            () async {},
          );
        }
        return DownloadTask(Future<File>.value(file), () async {});
      };

      final first = await manager.enqueue(track);
      await expectLater(first.result, throwsStateError);
      expect(manager.task(first.id)?.status, ManagedDownloadStatus.failed);

      final retry = await manager.retry(first.id);
      await expectLater(retry.result, throwsA(isA<FileSystemException>()));
      expect(manager.task(retry.id)?.status, ManagedDownloadStatus.failed);
      expect(saved, isEmpty);
      expect(attempts, 2);
    },
  );
}

Future<File> _audioFile(Directory root, String name, List<int> bytes) async {
  final file = File('${root.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}

class _FakeSource implements MusicSource {
  int started = 0;
  bool downloadEnabled = true;
  DownloadTask Function(MusicTrack, DownloadProgressCallback)? onStart;

  @override
  String get id => 'download_test';
  @override
  bool get isConfigured => true;
  @override
  bool get canDownload => downloadEnabled;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) async =>
      [];
  @override
  Future<String?> getStreamUrl(String trackId) async => null;
  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) {
    started++;
    return onStart!(track, onProgress);
  }

  @override
  String attributionFor(MusicTrack track) => 'Test catalog';
  @override
  void close() {}
}

class _Track implements MusicTrack {
  const _Track(this.id, {this.downloadAllowed = true});

  @override
  final String id;
  @override
  String get sourceId => 'download_test';
  @override
  String get title => 'Track $id';
  @override
  String get artist => 'Test artist';
  @override
  String get album => 'Test album';
  @override
  Duration get duration => const Duration(minutes: 2);
  @override
  String get streamUrl => 'https://catalog.example/$id.mp3';
  @override
  String? get downloadUrl => streamUrl;
  @override
  String? get artworkUrl => null;
  @override
  String? get licenseUrl => null;
  @override
  String? get pageUrl => null;
  @override
  final bool downloadAllowed;
  @override
  String? get codec => 'mp3';
  @override
  int? get bitrateKbps => null;

  @override
  Song toSong() => Song(
    id: '$sourceId:$id',
    filePath: streamUrl,
    title: title,
    artist: artist,
    album: album,
    albumArtist: artist,
    duration: duration,
    fileSize: 0,
    addedAt: DateTime.utc(2026),
    source: sourceId,
    streamUrl: streamUrl,
    downloadUrl: downloadUrl,
    downloadAllowed: downloadAllowed,
  );
}
