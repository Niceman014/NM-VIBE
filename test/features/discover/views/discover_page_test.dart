import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/sources/music_source.dart';
import 'package:nm_vibe/features/discover/views/discover_page.dart';
import 'package:nm_vibe/shared/providers/music_providers.dart';

void main() {
  testWidgets('shows the secure connection message for a TLS search failure', (
    tester,
  ) async {
    final repository = MusicRepository(sources: [_FailingArchiveSource()]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [musicRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: Scaffold(body: DiscoverPage())),
      ),
    );
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
  }) =>
      throw StateError('Downloads are not used by this test.');

  @override
  String attributionFor(MusicTrack track) => 'Internet Archive';

  @override
  void close() {}
}
