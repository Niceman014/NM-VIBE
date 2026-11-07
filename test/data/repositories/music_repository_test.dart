import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/repositories/music_search_ranking.dart';
import 'package:nm_vibe/data/sources/internet_archive_music_source.dart';
import 'package:nm_vibe/data/sources/music_source.dart';
import 'package:nm_vibe/data/models/song_model.dart';

void main() {
  test(
    'source-prefixed IDs route stream lookup and preserve catalog results',
    () async {
      final source = _FakeSource();
      final repository = MusicRepository(sources: [source]);

      final tracks = await repository.search('ambient', page: 2);
      expect(tracks.single.sourceId, 'catalog_test');
      expect(tracks.single.toSong().id, 'catalog_test:42');
      expect(source.lastPage, 2);
      expect(
        await repository.getStreamUrl('catalog_test:42'),
        source.track.streamUrl,
      );
      expect(repository.attributionFor(source.track), contains('catalog_test'));
    },
  );

  test('rejects malformed and unknown source IDs', () async {
    final repository = MusicRepository(sources: [_FakeSource()]);
    expect(() => repository.getStreamUrl('42'), throwsFormatException);
    expect(() => repository.getStreamUrl('unknown:42'), throwsStateError);
  });

  test('search pages query every active source with normalized text', () async {
    final catalog = _CatalogSource(
      'catalog_test',
      pages: {
        2: [_catalogTrack('catalog_test', 'ambient-2', title: 'Quiet Piano')],
      },
    );
    final archive = _CatalogSource(
      'internet_archive',
      pages: {
        2: [_archiveTrack('archive-2', title: 'Piano at Dawn')],
      },
    );
    final repository = MusicRepository(sources: [catalog, archive]);

    final page = await repository.searchPage('  AMBIENT   PIANO  ', page: 2);

    expect(catalog.queries, ['ambient piano']);
    expect(archive.queries, ['ambient piano']);
    expect(catalog.pagesRequested, [2]);
    expect(archive.pagesRequested, [2]);
    expect(page.tracks, hasLength(2));
    expect(page.hasMore, isTrue);
  });

  test('emits fast source results before a slower source completes', () async {
    final slowResult = Completer<List<MusicTrack>>();
    final repository = MusicRepository(
      sources: [
        _CatalogSource(
          'local',
          pages: {
            1: [_archiveTrack('local-fast', title: 'Fast local result')],
          },
        ),
        _CatalogSource(
          'internet_archive',
          pages: const {},
          pendingResult: slowResult,
        ),
      ],
    );
    final updates = <MusicSearchSourceUpdate>[];
    var searchCompleted = false;

    final search = repository.searchPage('fast', onSourceUpdate: updates.add);
    unawaited(search.then((_) => searchCompleted = true));
    await Future<void>.delayed(Duration.zero);

    expect(updates, hasLength(1));
    expect(updates.single.sourceId, 'local');
    expect(updates.single.tracks.single.title, 'Fast local result');
    expect(searchCompleted, isFalse);

    slowResult.complete([_archiveTrack('archive-slow', title: 'Slow result')]);
    final page = await search;
    expect(page.tracks.map((track) => track.title), [
      'Fast local result',
      'Slow result',
    ]);
    expect(updates.map((update) => update.sourceId), [
      'local',
      'internet_archive',
    ]);
  });

  test('suppresses conservative cross-provider duplicate recordings', () async {
    final repository = MusicRepository(
      sources: [
        _CatalogSource(
          'catalog_test',
          pages: {
            1: [
              _catalogTrack(
                'catalog_test',
                'j-1',
                title: 'Afterglow',
                artist: 'Nova',
                seconds: 185,
              ),
            ],
          },
        ),
        _CatalogSource(
          'internet_archive',
          pages: {
            1: [
              _archiveTrack(
                'ia-1',
                title: ' afterglow ',
                artist: 'NOVA',
                seconds: 186,
              ),
              _archiveTrack(
                'ia-2',
                title: 'Afterglow',
                artist: 'Nova',
                seconds: 205,
              ),
            ],
          },
        ),
      ],
    );

    final page = await repository.searchPage('afterglow');

    expect(page.tracks, hasLength(2));
    expect(page.tracks.map((track) => track.sourceId), [
      'catalog_test',
      'internet_archive',
    ]);
  });

  test(
    'ranks title, artist, multiword, and typo matches predictably',
    () async {
      final repository = MusicRepository(
        sources: [
          _CatalogSource(
            'internet_archive',
            pages: {
              1: [
                _archiveTrack('weak', title: 'Tum Hi Ho Live', artist: 'Other'),
                _archiveTrack(
                  'artist',
                  title: 'Aashiqui',
                  artist: 'Arijit Singh',
                ),
                _archiveTrack('exact', title: 'Tum Hi Ho'),
                _archiveTrack('partial', title: 'Tum Hi Ho (Acoustic)'),
                _archiveTrack('noise', title: 'Tum', artist: 'Hi Ho'),
                _archiveTrack(
                  'unrelated',
                  title: 'Evening Jazz',
                  artist: 'Quartet',
                ),
              ],
            },
          ),
        ],
      );

      final exact = await repository.searchPage('tum  hi   ho');
      expect(exact.tracks.first.id, 'exact');
      expect(
        exact.tracks.indexWhere((track) => track.id == 'exact'),
        lessThan(exact.tracks.indexWhere((track) => track.id == 'partial')),
      );
      expect(
        exact.tracks.indexWhere((track) => track.id == 'partial'),
        lessThan(exact.tracks.indexWhere((track) => track.id == 'noise')),
      );
      expect(exact.tracks.last.id, 'unrelated');

      final typo = rankMusicTracks('tumh iho', exact.tracks);
      expect(typo.first.id, 'exact');

      final artist = await repository.searchPage('arijit singh');
      expect(artist.tracks.first.id, 'artist');
    },
  );

  test('matches a bounded two-edit spelling mistake without noisy results', () {
    final matches = rankMusicTracks('blinding lght', [
      _archiveTrack('lights', title: 'Blinding Lights'),
      _archiveTrack('noise', title: 'Bright Night'),
    ]);

    expect(matches.map((track) => track.id), ['lights', 'noise']);
    final scores = matches
        .map(
          (track) => MusicSearchScorer('blinding lght').score(
            normalizeMusicSearchText(track.title),
            normalizeMusicSearchText(track.artist),
          ),
        )
        .toList();
    expect(scores.first, greaterThan(0));
    expect(scores.last, 0);
  });

  test('keeps live, remastered, and cover recordings distinct', () async {
    final repository = MusicRepository(
      sources: [
        _CatalogSource(
          'catalog_test',
          pages: {
            1: [
              _catalogTrack(
                'catalog_test',
                'remaster',
                title: 'Song',
                artist: 'Singer',
                seconds: 180,
                album: 'Song Remastered',
              ),
            ],
          },
        ),
        _CatalogSource(
          'internet_archive',
          pages: {
            1: [
              _archiveTrack(
                'live',
                title: 'Song (Live)',
                artist: 'Singer',
                seconds: 180,
              ),
              _archiveTrack(
                'original',
                title: 'Song',
                artist: 'Singer',
                seconds: 180,
              ),
              _archiveTrack(
                'cover',
                title: 'Song',
                artist: 'Different Singer',
                seconds: 180,
              ),
            ],
          },
        ),
      ],
    );
    final page = await repository.searchPage('song');
    expect(
      page.tracks.map((track) => track.id),
      containsAll(['original', 'live', 'remaster', 'cover']),
    );
  });

  test(
    'reports empty pages and keeps results when one provider fails',
    () async {
      final repository = MusicRepository(
        sources: [
          _CatalogSource(
            'catalog_test',
            pages: const {},
            failure: StateError('offline'),
          ),
          _CatalogSource(
            'internet_archive',
            pages: {
              1: [_archiveTrack('available', title: 'Available Song')],
            },
          ),
        ],
      );

      final page = await repository.searchPage('available');

      expect(page.tracks, hasLength(1));
      expect(page.failedSourceIds, ['catalog_test']);
      expect(page.hasMore, isTrue);

      final emptyPage = await MusicRepository(
        sources: [_CatalogSource('internet_archive', pages: const {})],
      ).searchPage('missing');
      expect(emptyPage.tracks, isEmpty);
      expect(emptyPage.hasMore, isFalse);
    },
  );

  test('throws when every remote provider fails', () async {
    final repository = MusicRepository(
      sources: [
        _CatalogSource(
          'internet_archive',
          pages: const {},
          failure: const FormatException('bad response'),
        ),
        _CatalogSource(
          'catalog_test',
          pages: const {},
          failure: StateError('offline'),
        ),
      ],
    );

    await expectLater(repository.searchPage('song'), throwsFormatException);
  });
}

class _FakeSource implements MusicSource {
  final track = _catalogTrack(
    'catalog_test',
    '42',
    title: 'Example',
    artist: 'Artist',
  );

  int? lastPage;

  @override
  String get id => 'catalog_test';

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => false;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) async {
    lastPage = page;
    return [track];
  }

  @override
  Future<String?> getStreamUrl(String trackId) async {
    expect(trackId, track.id);
    return track.streamUrl;
  }

  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) => throw StateError('Downloads are disabled.');

  @override
  String attributionFor(MusicTrack track) => 'Music via $id.';

  @override
  void close() {}
}

class _CatalogSource implements MusicSource {
  _CatalogSource(
    this.id, {
    required this.pages,
    this.failure,
    this.pendingResult,
  });

  @override
  final String id;
  final Map<int, List<MusicTrack>> pages;
  final Object? failure;
  final Completer<List<MusicTrack>>? pendingResult;
  final List<String> queries = <String>[];
  final List<int> pagesRequested = <int>[];

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => false;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) async {
    queries.add(query);
    pagesRequested.add(page);
    if (failure != null) throw failure!;
    if (pendingResult != null) return pendingResult!.future;
    return pages[page] ?? const <MusicTrack>[];
  }

  @override
  Future<String?> getStreamUrl(String trackId) async => null;

  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) => throw StateError('Not used in repository search tests.');

  @override
  String attributionFor(MusicTrack track) => 'Catalog $id';

  @override
  void close() {}
}

_TestTrack _catalogTrack(
  String sourceId,
  String id, {
  required String title,
  String artist = 'Artist',
  int seconds = 180,
  String album = 'Test album',
}) => _TestTrack(
  sourceId: sourceId,
  id: id,
  title: title,
  artist: artist,
  album: album,
  duration: Duration(seconds: seconds),
  streamUrl: 'https://catalog.example/$id.mp3',
);

class _TestTrack implements MusicTrack {
  const _TestTrack({
    required this.sourceId,
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.streamUrl,
  });

  @override
  final String sourceId;
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String album;
  @override
  final Duration duration;
  @override
  final String streamUrl;
  @override
  String? get downloadUrl => null;
  @override
  String? get artworkUrl => null;
  @override
  String? get licenseUrl => null;
  @override
  String? get pageUrl => null;
  @override
  bool get downloadAllowed => false;
  @override
  String? get codec => null;
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
  );
}

InternetArchiveTrack _archiveTrack(
  String id, {
  required String title,
  String artist = 'Artist',
  int seconds = 180,
}) => InternetArchiveTrack(
  id: id,
  title: title,
  artist: artist,
  duration: Duration(seconds: seconds),
  streamUrl: 'https://archive.org/download/$id/audio.mp3',
  downloadUrl: 'https://archive.org/download/$id/audio.mp3',
  licenseStatement: 'No license declared',
  codec: 'MP3',
  bitrateKbps: null,
);
