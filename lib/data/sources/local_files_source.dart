import 'dart:async';
import 'dart:collection';

import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/music_search_ranking.dart';

import 'music_source.dart';

class LocalMusicTrack implements MusicTrack {
  const LocalMusicTrack(this.song);

  final Song song;

  @override
  String get sourceId => 'local';
  @override
  String get id => song.id;
  @override
  String get title => song.displayTitle;
  @override
  String get artist => song.displayArtist;
  @override
  String get album => song.displayAlbum;
  @override
  Duration get duration => song.duration;
  @override
  String get streamUrl => song.streamUrl ?? song.filePath;
  @override
  String? get downloadUrl => null;
  @override
  String? get artworkUrl => song.remoteArtworkUrl;
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
  Song toSong() => song;
}

class LocalFilesMusicSource implements MusicSource {
  LocalFilesMusicSource(this._libraryRepository);

  final LibraryRepository _libraryRepository;
  List<_IndexedSong>? _index;
  Map<String, _IndexedSong> _indexById = const <String, _IndexedSong>{};
  Future<List<_IndexedSong>>? _indexFuture;
  StreamSubscription<List<Song>>? _subscription;
  final LinkedHashMap<String, List<MusicTrack>> _queryCache =
      LinkedHashMap<String, List<MusicTrack>>();

  static const int _pageSize = 30;

  @override
  String get id => 'local';

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => false;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) async {
    final normalized = normalizeMusicSearchText(query);
    final cached = _queryCache.remove(normalized);
    if (cached != null) {
      _queryCache[normalized] = cached;
      return _page(cached, page);
    }
    final songs = await _loadIndex();
    final scorer = MusicSearchScorer(normalized);
    final matches = normalized.isEmpty
        ? songs
        : songs.where(
            (entry) =>
                scorer.score(entry.title, entry.artist, album: entry.album) > 0,
          );
    final resultTracks = normalized.isEmpty
        ? songs
              .map((entry) => LocalMusicTrack(entry.song))
              .toList(growable: false)
        : _rankMatches(matches, scorer);
    _queryCache[normalized] = resultTracks;
    if (_queryCache.length > 4) _queryCache.remove(_queryCache.keys.first);
    return _page(resultTracks, page);
  }

  @override
  Future<String?> getStreamUrl(String trackId) async {
    final song = await _libraryRepository.getSong(trackId);
    return song?.streamUrl ?? song?.filePath;
  }

  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) => throw StateError('Local tracks are already stored on this device.');

  @override
  String attributionFor(MusicTrack track) => 'From your local music library.';

  @override
  void close() => unawaited(_subscription?.cancel());

  Future<List<_IndexedSong>> _loadIndex() {
    if (_index != null) return Future.value(_index);
    return _indexFuture ??= () async {
      final ready = Completer<List<_IndexedSong>>();
      _subscription = _libraryRepository.watchSongs().listen(
        (songs) {
          final nextIndex = <_IndexedSong>[];
          final nextIndexById = <String, _IndexedSong>{};
          for (final song in songs) {
            final prior = _indexById[song.id];
            final entry = prior != null && prior.hasSameSearchFields(song)
                ? prior.withSong(song)
                : _IndexedSong(song);
            nextIndex.add(entry);
            nextIndexById[song.id] = entry;
          }
          _index = nextIndex;
          _indexById = nextIndexById;
          _queryCache.clear();
          if (!ready.isCompleted) ready.complete(_index);
        },
        onError: (Object error, StackTrace stack) {
          if (!ready.isCompleted) ready.completeError(error, stack);
        },
      );
      try {
        return await ready.future;
      } catch (_) {
        _indexFuture = null;
        rethrow;
      }
    }();
  }

  List<MusicTrack> _page(List<MusicTrack> tracks, int page) {
    final start = (page - 1) * _pageSize;
    if (start >= tracks.length) return const <MusicTrack>[];
    return tracks.skip(start).take(_pageSize).toList(growable: false);
  }

  List<MusicTrack> _rankMatches(
    Iterable<_IndexedSong> matches,
    MusicSearchScorer scorer,
  ) {
    final ranked =
        matches.indexed
            .map(
              (entry) => (
                entry.$1,
                entry.$2,
                scorer.score(
                  entry.$2.title,
                  entry.$2.artist,
                  album: entry.$2.album,
                ),
              ),
            )
            .toList()
          ..sort((left, right) {
            final scoreOrder = right.$3.compareTo(left.$3);
            return scoreOrder == 0 ? left.$1.compareTo(right.$1) : scoreOrder;
          });
    return ranked
        .map((entry) => LocalMusicTrack(entry.$2.song))
        .toList(growable: false);
  }
}

class _IndexedSong {
  _IndexedSong(this.song)
    : title = normalizeMusicSearchText(song.displayTitle),
      artist = normalizeMusicSearchText(song.displayArtist),
      album = normalizeMusicSearchText(song.displayAlbum);

  const _IndexedSong._(this.song, this.title, this.artist, this.album);

  final Song song;
  final String title;
  final String artist;
  final String album;

  bool hasSameSearchFields(Song other) =>
      song.title == other.title &&
      song.artist == other.artist &&
      song.album == other.album &&
      (song.title.trim().isNotEmpty || song.filePath == other.filePath);

  _IndexedSong withSong(Song song) =>
      _IndexedSong._(song, title, artist, album);
}
