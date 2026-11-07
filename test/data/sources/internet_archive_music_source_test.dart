import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nm_vibe/data/downloads/download_storage.dart';
import 'package:nm_vibe/data/sources/internet_archive_music_source.dart';
import 'package:nm_vibe/data/sources/music_source.dart';

void main() {
  test(
    'only explicit public-domain, CC0, CC BY and CC BY-SA terms allow copies',
    () {
      expect(internetArchiveCopyAllowed('Public Domain'), isTrue);
      expect(internetArchiveCopyAllowed('CC0'), isTrue);
      expect(
        internetArchiveCopyAllowed(
          'https://creativecommons.org/publicdomain/mark/1.0/',
        ),
        isTrue,
      );
      expect(
        internetArchiveCopyAllowed(
          'https://creativecommons.org/licenses/by/4.0/',
        ),
        isTrue,
      );
      expect(
        internetArchiveCopyAllowed(
          'https://creativecommons.org/licenses/by-sa/3.0/',
        ),
        isTrue,
      );
      expect(
        internetArchiveCopyAllowed(
          'https://creativecommons.org/licenses/by-nc/4.0/',
        ),
        isFalse,
      );
      expect(
        internetArchiveCopyAllowed(
          'https://creativecommons.org/licenses/by-nd/4.0/',
        ),
        isFalse,
      );
      expect(internetArchiveCopyAllowed('No license declared'), isFalse);
    },
  );

  test('search reads item license metadata and exposes stream-only unknown items', () async {
    final service = InternetArchiveService(
      client: MockClient((request) async {
        if (request.url.path == '/advancedsearch.php') {
          return http.Response('''{"response":{"docs":[
            {"identifier":"allowed-audio","title":"Allowed","creator":"Artist"},
            {"identifier":"unknown-audio","title":"Unknown","creator":"Artist"}
          ]}}''', 200);
        }
        final id = request.url.pathSegments.last;
        final license = id == 'allowed-audio'
            ? 'https://creativecommons.org/licenses/by/4.0/'
            : null;
        return http.Response(
          '''{"metadata":${license == null ? '{}' : '{"licenseurl":"$license"}'},
          "files":[{"name":"track.mp3","size":"6","bitrate":"192"}]}''',
          200,
        );
      }),
    );
    addTearDown(service.close);

    final tracks = await service.search('piano');
    expect(tracks, hasLength(2));
    expect(tracks.first.downloadAllowed, isTrue);
    expect(tracks.first.sourceId, 'internet_archive');
    expect(tracks.first.pageUrl, 'https://archive.org/details/allowed-audio');
    expect(tracks.first.bitrateKbps, 192);
    expect(tracks.last.downloadAllowed, isFalse);
    expect(tracks.last.licenseStatement, 'No license declared');
  });

  test('search normalizes case and whitespace, matches title and creator prefixes, and pages', () async {
    Uri? requested;
    final service = InternetArchiveService(
      client: MockClient((request) async {
        requested = request.url;
        return http.Response('{"response":{"docs":[]}}', 200);
      }),
    );
    addTearDown(service.close);

    await service.search('  CÉLINE   DION ', page: 3);

    expect(
      requested!.queryParameters['q'],
      'mediatype:audio AND ((title:(céline* AND dion*)) OR '
      '(creator:(céline* AND dion*)))',
    );
    expect(requested!.queryParameters['rows'], '20');
    expect(requested!.queryParameters['page'], '3');
  });

  test(
    'punctuation-only queries return empty without searching the whole archive',
    () async {
      var requests = 0;
      final service = InternetArchiveService(
        client: MockClient((_) async {
          requests++;
          return http.Response('{"response":{"docs":[]}}', 200);
        }),
      );
      addTearDown(service.close);

      expect(await service.search('!@#'), isEmpty);
      expect(requests, 0);
    },
  );

  test('interrupted transfers leave no corrupt file; startup removes abandoned part files', () async {
    final temp = await Directory.systemTemp.createTemp(
      'nmvibe_archive_restart_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final root = Directory('${temp.path}${Platform.pathSeparator}downloads');
    final storage = DownloadStorage(rootDirectoryOverride: root);
    final service = InternetArchiveService(
      client: MockClient((_) async => http.Response('', 500)),
      storage: storage,
      downloadClientFactory: _InterruptedClient.new,
    );
    addTearDown(service.close);
    const track = InternetArchiveTrack(
      id: 'restart-check',
      title: 'Interrupted transfer',
      artist: 'Test',
      duration: Duration(seconds: 1),
      streamUrl: 'https://archive.org/download/restart-check/audio.mp3',
      downloadUrl: 'https://archive.org/download/restart-check/audio.mp3',
      licenseStatement: 'CC0',
      codec: 'MP3',
      bitrateKbps: null,
      expectedSizeBytes: 100,
    );
    final task = service.startDownload(track, onProgress: (_, _) {});
    await expectLater(task.result, throwsFormatException);
    final sourceDir = Directory(
      '${root.path}${Platform.pathSeparator}internet_archive',
    );
    expect(await sourceDir.list().toList(), isEmpty);

    final abandoned = File(
      '${sourceDir.path}${Platform.pathSeparator}killed.part',
    );
    await sourceDir.create(recursive: true);
    await abandoned.writeAsBytes([1, 2, 3]);
    await DownloadStorage.cleanupPartialFiles(rootDirectory: root);
    expect(await abandoned.exists(), isFalse);
    expect(await sourceDir.list().toList(), isEmpty);
  });

  test('successful downloads report progress and persist complete download records', () async {
    final temp = await Directory.systemTemp.createTemp(
      'nmvibe_archive_download_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final storage = DownloadStorage(
      rootDirectoryOverride: Directory(
        '${temp.path}${Platform.pathSeparator}downloads',
      ),
    );
    final service = InternetArchiveService(
      client: MockClient((_) async => http.Response('', 500)),
      storage: storage,
      downloadClientFactory: () => _BytesClient([1, 2, 3, 4]),
    );
    addTearDown(service.close);
    const track = InternetArchiveTrack(
      id: 'complete-check',
      title: 'Complete transfer',
      artist: 'Test',
      duration: Duration(seconds: 1),
      streamUrl: 'https://archive.org/download/complete-check/audio.mp3',
      downloadUrl: 'https://archive.org/download/complete-check/audio.mp3',
      licenseStatement: 'CC0',
      codec: 'MP3',
      bitrateKbps: 128,
    );
    final updates = <(int, int?)>[];
    final task = service.startDownload(
      track,
      onProgress: (done, total) => updates.add((done, total)),
    );
    final file = await task.result;
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(updates, [(4, 4)]);
    final records = await storage.records();
    expect(records, hasLength(1));
    expect(records.single.source, 'internet_archive');
    expect(records.single.codec, 'MP3');
    expect(records.single.bitrateKbps, 128);
    expect(records.single.license, 'CC0');
    expect(records.single.sizeBytes, 4);
  });

  test(
    'replaces an unregistered final-name file instead of trusting it',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'nmvibe_archive_orphan_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final root = Directory('${temp.path}${Platform.pathSeparator}downloads');
      final itemDirectory = Directory(
        '${root.path}${Platform.pathSeparator}internet_archive',
      );
      await itemDirectory.create(recursive: true);
      final orphan = File(
        '${itemDirectory.path}${Platform.pathSeparator}orphan-check.mp3',
      );
      await orphan.writeAsBytes([9, 9]);
      final storage = DownloadStorage(rootDirectoryOverride: root);
      final service = InternetArchiveService(
        client: MockClient((_) async => http.Response('', 500)),
        storage: storage,
        downloadClientFactory: () => _BytesClient([1, 2, 3, 4]),
      );
      addTearDown(service.close);
      const track = InternetArchiveTrack(
        id: 'orphan-check',
        title: 'Recovered transfer',
        artist: 'Test',
        duration: Duration(seconds: 1),
        streamUrl: 'https://archive.org/download/orphan-check/audio.mp3',
        downloadUrl: 'https://archive.org/download/orphan-check/audio.mp3',
        licenseStatement: 'CC0',
        codec: 'MP3',
        bitrateKbps: 128,
        expectedSizeBytes: 4,
      );

      final file = await service
          .startDownload(track, onProgress: (_, _) {})
          .result;

      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      expect((await storage.records()).single.sizeBytes, 4);
    },
  );

  test('cancel stops the transfer and removes its partial file', () async {
    final temp = await Directory.systemTemp.createTemp(
      'nmvibe_archive_cancel_',
    );
    addTearDown(() => temp.delete(recursive: true));
    final root = Directory('${temp.path}${Platform.pathSeparator}downloads');
    final slow = _SlowClient();
    final service = InternetArchiveService(
      client: MockClient((_) async => http.Response('', 500)),
      storage: DownloadStorage(rootDirectoryOverride: root),
      downloadClientFactory: () => slow,
    );
    addTearDown(service.close);
    const track = InternetArchiveTrack(
      id: 'cancel-check',
      title: 'Cancel transfer',
      artist: 'Test',
      duration: Duration(seconds: 1),
      streamUrl: 'https://archive.org/download/cancel-check/audio.mp3',
      downloadUrl: 'https://archive.org/download/cancel-check/audio.mp3',
      licenseStatement: 'CC0',
      codec: 'MP3',
      bitrateKbps: null,
      expectedSizeBytes: 100,
    );
    final task = service.startDownload(track, onProgress: (_, _) {});
    await slow.started.future;
    slow.controller.add([1, 2, 3]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await task.cancel();
    await expectLater(task.result, throwsA(isA<DownloadCancelled>()));
    final sourceDir = Directory(
      '${root.path}${Platform.pathSeparator}internet_archive',
    );
    expect(await sourceDir.list().toList(), isEmpty);
  });

  test(
    'Wi-Fi-only setting blocks a download when Wi-Fi is unavailable',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'nmvibe_archive_wifi_',
      );
      addTearDown(() => temp.delete(recursive: true));
      final root = Directory('${temp.path}${Platform.pathSeparator}downloads');
      final service = InternetArchiveService(
        client: MockClient((_) async => http.Response('', 500)),
        storage: DownloadStorage(rootDirectoryOverride: root),
        wifiOnly: () => true,
        hasWifi: () async => false,
      );
      addTearDown(service.close);
      const track = InternetArchiveTrack(
        id: 'wifi-check',
        title: 'Wi-Fi guarded transfer',
        artist: 'Test',
        duration: Duration(seconds: 1),
        streamUrl: 'https://archive.org/download/wifi-check/audio.mp3',
        downloadUrl: 'https://archive.org/download/wifi-check/audio.mp3',
        licenseStatement: 'CC0',
        codec: 'MP3',
        bitrateKbps: null,
      );
      final task = service.startDownload(track, onProgress: (_, _) {});
      await expectLater(task.result, throwsA(isA<StateError>()));
      expect(await service.downloadedBytes(), 0);
    },
  );
}

class _InterruptedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value([1, 2, 3]),
        200,
        contentLength: 100,
        request: request,
      );
}

class _BytesClient extends http.BaseClient {
  _BytesClient(this.bytes);
  final List<int> bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        200,
        contentLength: bytes.length,
        request: request,
      );
}

class _SlowClient extends http.BaseClient {
  final controller = StreamController<List<int>>();
  final started = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!started.isCompleted) started.complete();
    return http.StreamedResponse(controller.stream, 200, request: request);
  }

  @override
  void close() {
    if (!controller.isClosed) controller.close();
  }
}
