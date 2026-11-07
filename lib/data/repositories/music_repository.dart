import '../sources/music_source.dart';
import 'music_search_ranking.dart';

const int _maximumSearchPage = 1000;

final class MusicSearchPage {
  const MusicSearchPage({
    required this.tracks,
    required this.hasMore,
    this.failedSourceIds = const <String>[],
  });

  final List<MusicTrack> tracks;
  final bool hasMore;
  final List<String> failedSourceIds;
}

/// Results from one provider as soon as that provider finishes its search.
final class MusicSearchSourceUpdate {
  const MusicSearchSourceUpdate({
    required this.sourceId,
    this.tracks = const <MusicTrack>[],
    this.failed = false,
  });

  final String sourceId;
  final List<MusicTrack> tracks;
  final bool failed;
}

typedef MusicSearchProgressCallback = void Function(
  MusicSearchSourceUpdate update,
);

/// Combines enabled catalogs and routes source-specific operations by the
/// source-prefixed track ID (`source:id`).
class MusicRepository {
  MusicRepository({required List<MusicSource> sources})
    : _sources = List<MusicSource>.unmodifiable(sources);

  final List<MusicSource> _sources;

  /// True only when an online catalog is ready; the local library is always
  /// available but must not hide the Discover setup state.
  bool get isConfigured =>
      _sources.any((source) => source.id != 'local' && source.isConfigured);
  bool isSourceConfigured(String sourceId) =>
      _sourceFor(sourceId)?.isConfigured ?? false;
  bool get hasOfflineDownloadsEnabled =>
      _sources.any((source) => source.canDownload);

  Future<List<MusicTrack>> search(String query, {int page = 1}) async =>
      (await searchPage(query, page: page)).tracks;

  Future<MusicSearchPage> searchPage(
    String query, {
    int page = 1,
    MusicSearchProgressCallback? onSourceUpdate,
  }) async {
    if (page < 1 || page > _maximumSearchPage) {
      throw ArgumentError.value(
        page,
        'page',
        'Must be between 1 and $_maximumSearchPage.',
      );
    }
    final normalizedQuery = query
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final enabled = _sources.where((source) => source.isConfigured).toList();
    if (enabled.isEmpty) {
      return const MusicSearchPage(tracks: <MusicTrack>[], hasMore: false);
    }

    final remoteErrors = <Object>[];
    final failedSourceIds = <String>[];
    final sourceResults = List<List<MusicTrack>>.filled(
      enabled.length,
      const <MusicTrack>[],
    );
    await Future.wait(
      enabled.indexed.map((entry) async {
        final (index, source) = entry;
        try {
          final tracks = await source.search(normalizedQuery, page: page);
          sourceResults[index] = tracks;
          onSourceUpdate?.call(
            MusicSearchSourceUpdate(
              sourceId: source.id,
              tracks: rankMusicTracks(normalizedQuery, tracks),
            ),
          );
        } catch (error) {
          if (source.id != 'local') {
            remoteErrors.add(error);
            failedSourceIds.add(source.id);
            onSourceUpdate?.call(
              MusicSearchSourceUpdate(sourceId: source.id, failed: true),
            );
          }
        }
      }),
    );
    final results = rankMusicTracks(
      normalizedQuery,
      deduplicateMusicTracks(sourceResults.expand((tracks) => tracks)),
    );
    final Object? remoteError = remoteErrors.isEmpty
        ? null
        : remoteErrors.first;
    if (results.isEmpty && remoteError != null) throw remoteError;
    return MusicSearchPage(
      tracks: results,
      hasMore:
          page < _maximumSearchPage &&
          sourceResults.any((tracks) => tracks.isNotEmpty),
      failedSourceIds: List<String>.unmodifiable(failedSourceIds),
    );
  }

  Future<String?> getStreamUrl(String sourceTrackId) {
    final (source, trackId) = _resolve(sourceTrackId);
    return source.getStreamUrl(trackId);
  }

  bool canDownload(MusicTrack track) {
    final source = _sourceFor(track.sourceId);
    return source != null && source.canDownload && track.downloadAllowed;
  }

  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) {
    final source = _sourceFor(track.sourceId);
    if (source == null) {
      throw StateError('The ${track.sourceId} source is not enabled.');
    }
    if (!source.canDownload || !track.downloadAllowed) {
      throw StateError('This source does not allow offline downloads.');
    }
    return source.startDownload(track, onProgress: onProgress);
  }

  String attributionFor(MusicTrack track) =>
      _sourceFor(track.sourceId)?.attributionFor(track) ?? '';

  (MusicSource, String) _resolve(String sourceTrackId) {
    final separator = sourceTrackId.indexOf(':');
    if (separator <= 0 || separator == sourceTrackId.length - 1) {
      throw FormatException('Track ID must include a source prefix.');
    }
    final sourceId = sourceTrackId.substring(0, separator);
    final trackId = sourceTrackId.substring(separator + 1);
    final source = _sourceFor(sourceId);
    if (source == null) {
      throw StateError('The $sourceId source is not enabled.');
    }
    return (source, trackId);
  }

  MusicSource? _sourceFor(String id) {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  void close() {
    for (final source in _sources) {
      source.close();
    }
  }
}

/// Removes repeated provider IDs and conservative cross-provider matches.
/// Cross-provider suppression requires title, artist, and duration within two
/// seconds, avoiding guesses based on title alone.
List<MusicTrack> deduplicateMusicTracks(Iterable<MusicTrack> tracks) {
  final unique = <MusicTrack>[];
  final seenIds = <String>{};
  final crossProvider = <String, List<MusicTrack>>{};

  for (final track in tracks) {
    final identity = '${track.sourceId}:${track.id}';
    if (!seenIds.add(identity)) continue;

    final title = _normalizedMetadata(track.title);
    final artist = _normalizedMetadata(track.artist);
    if (track.sourceId != 'local' &&
        title.isNotEmpty &&
        artist.isNotEmpty &&
        track.duration.inSeconds > 0 &&
        !_hasRecordingQualifier(track)) {
      final key = '$title|$artist';
      final priorMatches = crossProvider.putIfAbsent(key, () => <MusicTrack>[]);
      final duplicate = priorMatches.any(
        (prior) =>
            prior.sourceId != track.sourceId &&
            !_hasRecordingQualifier(prior) &&
            (prior.duration.inSeconds - track.duration.inSeconds).abs() <= 2,
      );
      if (duplicate) continue;
      priorMatches.add(track);
    }
    unique.add(track);
  }
  return List<MusicTrack>.unmodifiable(unique);
}

String _normalizedMetadata(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

bool _hasRecordingQualifier(MusicTrack track) => RegExp(
  r'\b(live|remaster(?:ed)?|cover|acoustic|demo|remix|radio edit|extended mix)\b',
  caseSensitive: false,
).hasMatch('${track.title} ${track.album}');
