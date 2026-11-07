import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/features/player/controllers/playback_source_resolver.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'nmvibe_playback_',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('keeps a valid downloaded file for offline playback', () async {
    final localFile = File('${temporaryDirectory.path}/track.wav');
    await localFile.writeAsBytes(_silentWav());

    final song = _downloadedSong(localFile.path);
    final resolved = await prepareSongForPlayback(song);

    expect(resolved.filePath, localFile.path);
    expect(resolved.isDownloaded, isTrue);
  });

  test(
    'falls back from a missing download to its original provider stream',
    () async {
      final song = _downloadedSong('${temporaryDirectory.path}/missing.mp3');

      final resolved = await prepareSongForPlayback(song);

      expect(resolved.filePath, song.streamUrl);
      expect(resolved.streamUrl, song.streamUrl);
      expect(resolved.isDownloaded, isFalse);
    },
  );

  test('falls back when the downloaded file is empty and unusable', () async {
    final emptyFile = File('${temporaryDirectory.path}/empty.mp3');
    await emptyFile.writeAsBytes(const []);
    final song = _downloadedSong(emptyFile.path);

    final resolved = await prepareSongForPlayback(song);

    expect(resolved.filePath, song.streamUrl);
    expect(resolved.isDownloaded, isFalse);
  });

  test(
    'does not treat download permission as a streaming requirement',
    () async {
      final song = _downloadedSong('${temporaryDirectory.path}/missing.mp3')
          .copyWith(downloadAllowed: false);

      final resolved = await prepareSongForPlayback(song);

      expect(resolved.filePath, song.streamUrl);
      expect(resolved.isDownloaded, isFalse);
    },
  );

  test(
    'rejects fallback when the provider or stream URL is unavailable',
    () async {
      final song = _downloadedSong(
        '${temporaryDirectory.path}/missing.mp3',
        id: 'local:track-1',
        source: null,
        streamUrl: null,
      );

      await expectLater(
        prepareSongForPlayback(song),
        throwsA(isA<PlaybackRecoveryException>()),
      );
    },
  );

  test('rejects a stream URL outside the track provider', () async {
    final song = _downloadedSong('${temporaryDirectory.path}/missing.mp3')
        .copyWith(streamUrl: 'https://example.invalid/track.mp3');

    await expectLater(
      prepareSongForPlayback(song),
      throwsA(isA<PlaybackRecoveryException>()),
    );
  });

  test(
    'provider failures become a clear message without raw exception text',
    () {
      expect(
        playbackFailureMessage(Exception('private provider response')),
        'Could not play this track. Check the file or your connection.',
      );
    },
  );

  test('leaves a non-downloaded song unchanged', () async {
    final song = _downloadedSong('${temporaryDirectory.path}/missing.mp3')
        .copyWith(isDownloaded: false);

    expect(await prepareSongForPlayback(song), same(song));
  });
}

Song _downloadedSong(
  String filePath, {
  String id = 'internet_archive:track-1',
  String? source = 'internet_archive',
  String? streamUrl = 'https://archive.org/download/track-1/track.mp3',
}) => Song(
  id: id,
  filePath: filePath,
  title: 'Track one',
  artist: 'Artist',
  album: 'Album',
  albumArtist: 'Artist',
  duration: const Duration(minutes: 2),
  fileSize: 3,
  addedAt: DateTime.utc(2026),
  source: source,
  streamUrl: streamUrl,
  downloadAllowed: true,
  isDownloaded: true,
);

Uint8List _silentWav() {
  final bytes = Uint8List(46);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, 38, Endian.little);
  bytes.setRange(8, 12, 'WAVE'.codeUnits);
  bytes.setRange(12, 16, 'fmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, 2, Endian.little);
  data.setInt16(44, 0, Endian.little);
  return bytes;
}
