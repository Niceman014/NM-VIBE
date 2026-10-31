import '../sources/music_source.dart';

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

  Future<List<MusicTrack>> search(String query, {int page = 1}) async {
    if (page < 1) throw ArgumentError.value(page, 'page', 'Must be positive.');
    final enabled = _sources.where((source) => source.isConfigured).toList();
    if (enabled.isEmpty) return const <MusicTrack>[];

    final remoteErrors = <Object>[];
    final sourceResults = await Future.wait(
      enabled.map((source) async {
        try {
          return await source.search(query, page: page);
        } catch (error) {
          if (source.id != 'local') remoteErrors.add(error);
          return const <MusicTrack>[];
        }
      }),
    );
    final results = sourceResults.expand((tracks) => tracks).toList();
    final Object? remoteError = remoteErrors.isEmpty
        ? null
        : remoteErrors.first;
    if (results.isEmpty && remoteError != null) throw remoteError;
    return results;
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
