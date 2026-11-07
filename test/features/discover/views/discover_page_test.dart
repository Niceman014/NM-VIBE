import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/downloads/offline_index.dart';
import 'package:nm_vibe/data/repositories/in_memory_library_repository.dart';
import 'package:nm_vibe/data/sources/internet_archive_music_source.dart';
import 'package:nm_vibe/data/sources/music_source.dart';
import 'package:nm_vibe/features/discover/views/discover_page.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/shared/providers/music_providers.dart';

void main() {
  testWidgets('shows a completed source while another source is pending', (
    tester,
  ) async {
    final delayedSource = _DelayedCatalogSource();
    final repository = MusicRepository(
      sources: [_PagedArchiveSource(), delayedSource],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(_discoverApp(repository));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('First page song'), findsWidgets);
    expect(find.text('Delayed source result'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    delayedSource.result.complete([
      _archiveTrack('delayed', 'Delayed source result'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('First page song'), findsWidgets);
    expect(find.text('Delayed source result'), findsWidgets);
  });

  testWidgets('shows the secure connection message for a TLS search failure', (
    tester,
  ) async {
    final repository = MusicRepository(sources: [_FailingArchiveSource()]);

    await tester.pumpWidget(_discoverApp(repository));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Could not make a secure connection. A VPN, proxy or antivirus may be blocking it. Check your network and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('certificate detail'), findsNothing);
  });

  testWidgets('loads the next provider page when Load more is tapped', (
    tester,
  ) async {
    final source = _PagedArchiveSource();
    final repository = MusicRepository(sources: [source]);
    addTearDown(repository.close);

    await tester.pumpWidget(_discoverApp(repository));
    await tester.pumpAndSettle();

    expect(find.text('First page song'), findsWidgets);
    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();

    expect(source.requestedPages, [1, 2]);
    expect(find.text('Second page song'), findsWidgets);
  });

  testWidgets('rapid query changes never display a stale response', (
    tester,
  ) async {
    final source = _RapidArchiveSource();
    final repository = MusicRepository(sources: [source]);
    addTearDown(repository.close);

    await tester.pumpWidget(_discoverApp(repository));
    await tester.pumpAndSettle();
    final searchField = find.byType(TextField);

    await tester.enterText(searchField, 'slow request');
    await tester.pump(const Duration(milliseconds: 401));
    expect(source.slowSearchStarted, isTrue);

    await tester.enterText(searchField, 'quick request');
    await tester.pump(const Duration(milliseconds: 401));
    await tester.pumpAndSettle();
    expect(find.text('Quick result'), findsWidgets);

    source.slowSearch.complete([_archiveTrack('slow', 'Slow stale result')]);
    await tester.pumpAndSettle();
    expect(find.text('Slow stale result'), findsNothing);
    expect(find.text('Quick result'), findsWidgets);
  });

  testWidgets('shows Save Offline only when source and track allow it', (
    tester,
  ) async {
    final repository = MusicRepository(
      sources: [
        _PagedArchiveSource(downloadEnabled: true, trackLicense: 'CC0'),
      ],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(_discoverApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More track actions').first);
    await tester.pumpAndSettle();

    expect(find.text('Save offline'), findsOneWidget);
  });

  testWidgets('explains why a stream-only source cannot save offline', (
    tester,
  ) async {
    final repository = MusicRepository(
      sources: [
        _PagedArchiveSource(downloadEnabled: false, trackLicense: 'CC0'),
      ],
    );
    addTearDown(repository.close);

    await tester.pumpWidget(_discoverApp(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More track actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Why can’t I save offline?'));
    await tester.pumpAndSettle();

    expect(
      find.text('This music source does not permit offline downloads.'),
      findsOneWidget,
    );
  });
}

Widget _discoverApp(MusicRepository repository) => ProviderScope(
  overrides: [
    musicRepositoryProvider.overrideWithValue(repository),
    libraryRepositoryProvider.overrideWith((ref) {
      final library = InMemoryLibraryRepository();
      ref.onDispose(() => unawaited(library.close()));
      return library;
    }),
    songsProvider.overrideWith(
      (ref) => ref.watch(libraryRepositoryProvider).watchSongs(),
    ),
    offlineIndexProvider.overrideWith(
      (ref) => Future.value(const <OfflineTrackEntry>[]),
    ),
  ],
  child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
);

class _DelayedCatalogSource implements MusicSource {
  final Completer<List<MusicTrack>> result = Completer<List<MusicTrack>>();

  @override
  String get id => 'catalog_test';

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => false;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) =>
      result.future;

  @override
  Future<String?> getStreamUrl(String trackId) async => null;

  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) => throw StateError('Not used in incremental search test.');

  @override
  String attributionFor(MusicTrack track) => 'Delayed test source';

  @override
  void close() {}
}

class _FailingArchiveSource implements MusicSource {
  @override
  String get id => 'internet_archive';

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => true;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) async {
    throw const HandshakeException('certificate detail');
  }

  @override
  Future<String?> getStreamUrl(String trackId) async => null;

  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) => throw StateError('Downloads are not used by this test.');

  @override
  String attributionFor(MusicTrack track) => 'Internet Archive';

  @override
  void close() {}
}

class _PagedArchiveSource implements MusicSource {
  _PagedArchiveSource({
    this.downloadEnabled = false,
    this.trackLicense = 'No license declared',
  });

  final bool downloadEnabled;
  final String trackLicense;
  final List<int> requestedPages = <int>[];

  @override
  String get id => 'internet_archive';

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => downloadEnabled;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) async {
    requestedPages.add(page);
    return switch (page) {
      1 => [_archiveTrack('first', 'First page song', license: trackLicense)],
      2 => [_archiveTrack('second', 'Second page song', license: trackLicense)],
      _ => const <MusicTrack>[],
    };
  }

  @override
  Future<String?> getStreamUrl(String trackId) async => null;

  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) => throw StateError('Not used in Discover pagination test.');

  @override
  String attributionFor(MusicTrack track) => 'Internet Archive';

  @override
  void close() {}
}

class _RapidArchiveSource implements MusicSource {
  final Completer<List<MusicTrack>> slowSearch = Completer<List<MusicTrack>>();
  bool slowSearchStarted = false;

  @override
  String get id => 'internet_archive';

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => false;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) {
    if (query == 'slow request') {
      slowSearchStarted = true;
      return slowSearch.future;
    }
    if (query == 'quick request') {
      return Future<List<MusicTrack>>.value([
        _archiveTrack('quick', 'Quick result'),
      ]);
    }
    return Future<List<MusicTrack>>.value(const <MusicTrack>[]);
  }

  @override
  Future<String?> getStreamUrl(String trackId) async => null;

  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) => throw StateError('Not used in Discover race test.');

  @override
  String attributionFor(MusicTrack track) => 'Internet Archive';

  @override
  void close() {}
}

InternetArchiveTrack _archiveTrack(
  String id,
  String title, {
  String license = 'No license declared',
}) => InternetArchiveTrack(
  id: id,
  title: title,
  artist: 'Example artist',
  duration: const Duration(minutes: 2),
  streamUrl: 'https://archive.org/download/$id/audio.mp3',
  downloadUrl: 'https://archive.org/download/$id/audio.mp3',
  licenseStatement: license,
  codec: 'MP3',
  bitrateKbps: null,
);
