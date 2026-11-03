import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:nm_vibe/features/updates/models/update_manifest.dart';
import 'package:nm_vibe/features/updates/services/open_page_strategy.dart';
import 'package:nm_vibe/features/updates/services/play_update_strategy.dart';
import 'package:nm_vibe/features/updates/services/update_strategy.dart';
import 'package:nm_vibe/features/updates/services/update_strategy_factory.dart';
import 'package:nm_vibe/features/updates/services/windows_installer_strategy.dart';

void main() {
  group('UpdateStrategyFactory', () {
    test('chooses the Google Play strategy for Android', () {
      expect(
        UpdateStrategyFactory.forPlatform(UpdatePlatform.android),
        isA<PlayUpdateStrategy>(),
      );
    });

    test('chooses the verified installer strategy for Windows', () {
      final strategy = UpdateStrategyFactory.forPlatform(
        UpdatePlatform.windows,
        backendUrl: 'https://updates.example.invalid',
        releaseMode: true,
      );
      expect(strategy, isA<WindowsInstallerStrategy>());
      strategy.dispose();
    });

    test(
      'chooses the open-page strategy for the other supported platforms',
      () {
        for (final platform in [
          UpdatePlatform.ios,
          UpdatePlatform.macos,
          UpdatePlatform.linux,
        ]) {
          final strategy = UpdateStrategyFactory.forPlatform(platform);
          expect(strategy, isA<OpenPageStrategy>());
          expect((strategy as OpenPageStrategy).platform, platform);
          strategy.dispose();
        }
      },
    );
  });

  test('Google Play API failures fall back to the Play listing', () async {
    Uri? openedUri;
    final strategy = PlayUpdateStrategy(
      checkForUpdate: () async => throw StateError('Play API unavailable'),
      packageName: () async => 'com.nmnext.nmvibe',
      open: (uri) async {
        openedUri = uri;
        return true;
      },
    );

    final result = await strategy.check(currentVersion: '1.0.0');
    expect(result.status, UpdateStatus.openedPage);
    expect(openedUri?.scheme, 'https');
    expect(openedUri?.host, 'play.google.com');
    expect(openedUri?.queryParameters['id'], 'com.nmnext.nmvibe');
    strategy.dispose();
  });

  group('WindowsInstallerStrategy', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'nmvibe-update-test-',
      );
    });

    tearDown(() async {
      await tempDirectory.delete(recursive: true);
    });

    test(
      'rejects an HTTP backend in release mode without making a request',
      () async {
        var sent = false;
        final strategy = WindowsInstallerStrategy(
          backendUrl: 'http://localhost:8787',
          releaseMode: true,
          client: _TestClient((_) async {
            sent = true;
            return http.StreamedResponse(const Stream.empty(), 200);
          }),
        );
        addTearDown(strategy.dispose);

        await expectLater(
          strategy.check(currentVersion: '1.0.0'),
          throwsA(isA<UpdateFailure>()),
        );
        expect(sent, isFalse);
      },
    );

    test(
      'reads the stable Windows manifest and enforces the minimum version',
      () async {
        Uri? requestUri;
        final payload = {
          'platform': 'windows',
          'channel': 'stable',
          'version': '1.2.0+3',
          'minSupportedVersion': '1.1.0+2',
          'releaseNotes': 'Required security update.',
          'sha256': List<String>.filled(64, 'a').join(),
          'sizeBytes': 1234,
          'downloadUrl': pendingUpdateUrl,
          'downloadConfigured': false,
        };
        final body = jsonEncode(payload);
        final strategy = WindowsInstallerStrategy(
          backendUrl: 'http://127.0.0.1:8787',
          releaseMode: false,
          client: _TestClient((request) async {
            requestUri = request.url;
            final bytes = utf8.encode(body);
            return http.StreamedResponse(
              Stream.value(bytes),
              200,
              contentLength: bytes.length,
            );
          }),
        );
        addTearDown(strategy.dispose);

        final result = await strategy.check(currentVersion: '1.0.0+1');
        expect(requestUri?.path, '/v1/updates/latest');
        expect(requestUri?.queryParameters, {
          'platform': 'windows',
          'channel': 'stable',
        });
        expect(result.status, UpdateStatus.available);
        expect(result.requiresUpdate, isTrue);
        expect(result.manifest?.downloadConfigured, isFalse);
      },
    );

    test(
      'hash mismatch deletes the partial file and never launches it',
      () async {
        final bytes = utf8.encode('installer bytes');
        var launched = false;
        final strategy = WindowsInstallerStrategy(
          backendUrl: 'https://updates.example.invalid',
          releaseMode: true,
          directoryProvider: () async => tempDirectory,
          launchInstaller: (_) async => launched = true,
          client: _TestClient(
            (_) async => http.StreamedResponse(
              Stream.value(bytes),
              200,
              contentLength: bytes.length,
            ),
          ),
        );
        addTearDown(strategy.dispose);

        await expectLater(
          strategy.install(
            _manifest(sha256: '0' * 64, sizeBytes: bytes.length),
            onProgress: (_, _) {},
          ),
          throwsA(isA<UpdateFailure>()),
        );
        expect(launched, isFalse);
        final files = await Directory(tempDirectory.path)
            .list(recursive: true)
            .where((entity) => entity is File)
            .toList();
        expect(files, isEmpty);
      },
    );

    test('removes a partial download after a stream interruption', () async {
      final bytes = utf8.encode('partial');
      Stream<List<int>> interrupted() async* {
        yield bytes;
        throw const SocketException('test interruption');
      }

      final strategy = WindowsInstallerStrategy(
        backendUrl: 'https://updates.example.invalid',
        releaseMode: true,
        directoryProvider: () async => tempDirectory,
        launchInstaller: (_) async {},
        client: _TestClient(
          (_) async =>
              http.StreamedResponse(interrupted(), 200, contentLength: 20),
        ),
      );
      addTearDown(strategy.dispose);

      await expectLater(
        strategy.install(
          _manifest(sha256: 'a' * 64, sizeBytes: 20),
          onProgress: (_, _) {},
        ),
        throwsA(isA<UpdateFailure>()),
      );
      final files = await Directory(tempDirectory.path)
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList();
      expect(files, isEmpty);
    });

    test('cancel aborts the request and removes its partial file', () async {
      final requestStarted = Completer<void>();
      final strategy = WindowsInstallerStrategy(
        backendUrl: 'https://updates.example.invalid',
        releaseMode: true,
        directoryProvider: () async => tempDirectory,
        launchInstaller: (_) async {},
        client: _TestClient((request) async {
          requestStarted.complete();
          final abortTrigger = (request as http.Abortable).abortTrigger!;
          await abortTrigger;
          throw const SocketException('cancelled');
        }),
      );
      addTearDown(strategy.dispose);

      final installation = strategy.install(
        _manifest(sha256: 'b' * 64, sizeBytes: 20),
        onProgress: (_, _) {},
      );
      await requestStarted.future;
      await strategy.cancel();
      await expectLater(installation, throwsA(isA<UpdateCancelled>()));
      final files = await Directory(tempDirectory.path)
          .list(recursive: true)
          .where((entity) => entity is File)
          .toList();
      expect(files, isEmpty);
    });

    test('launches only a complete file whose SHA-256 matches', () async {
      final bytes = utf8.encode('verified installer');
      String? launchedPath;
      final statuses = <UpdateStatus>[];
      final strategy = WindowsInstallerStrategy(
        backendUrl: 'https://updates.example.invalid',
        releaseMode: true,
        directoryProvider: () async => tempDirectory,
        launchInstaller: (path) async => launchedPath = path,
        client: _TestClient(
          (_) async => http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length,
          ),
        ),
      );
      addTearDown(strategy.dispose);

      await strategy.install(
        _manifest(
          sha256: sha256.convert(bytes).toString(),
          sizeBytes: bytes.length,
        ),
        onProgress: (status, _) => statuses.add(status),
      );
      expect(launchedPath, isNotNull);
      expect(await File(launchedPath!).readAsBytes(), bytes);
      expect(
        statuses,
        containsAll([
          UpdateStatus.downloading,
          UpdateStatus.verifying,
          UpdateStatus.launched,
        ]),
      );
    });

    test('startup cleanup removes abandoned .part files only', () async {
      final updates = Directory(
        '${tempDirectory.path}${Platform.pathSeparator}updates',
      );
      await updates.create();
      final partial = File(
        '${updates.path}${Platform.pathSeparator}interrupted.exe.part',
      );
      final verified = File(
        '${updates.path}${Platform.pathSeparator}verified.exe',
      );
      await partial.writeAsString('incomplete');
      await verified.writeAsString('preserve');

      await WindowsInstallerStrategy.cleanupPartialFiles(
        directoryProvider: () async => tempDirectory,
      );

      expect(await partial.exists(), isFalse);
      expect(await verified.exists(), isTrue);
    });
  });
}

UpdateManifest _manifest({required String sha256, required int sizeBytes}) =>
    UpdateManifest.fromJson({
      'platform': 'windows',
      'channel': 'stable',
      'version': '1.1.0+2',
      'minSupportedVersion': '1.0.0+1',
      'releaseNotes': 'Test update.',
      'sha256': sha256,
      'sizeBytes': sizeBytes,
      'downloadUrl': 'https://updates.example.invalid/setup.exe',
      'downloadConfigured': true,
    });

class _TestClient extends http.BaseClient {
  _TestClient(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
