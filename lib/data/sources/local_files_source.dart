import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/data/models/song_model.dart';
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
  const LocalFilesMusicSource(this._libraryRepository);

  final LibraryRepository _libraryRepository;

  static const int _pageSize = 30;

  @override
  String get id => 'local';

  @override
  bool get isConfigured => true;

  @override
  bool get canDownload => false;

  @override
  Future<List<MusicTrack>> search(String query, {required int page}) async {
    final normalized = query.trim().toLowerCase();
    final songs = await _libraryRepository.getSongs();
    final matches = normalized.isEmpty
        ? songs
        : songs.where((song) {
            return song.displayTitle.toLowerCase().contains(normalized) ||
                song.displayArtist.toLowerCase().contains(normalized) ||
                song.displayAlbum.toLowerCase().contains(normalized);
          });
    final start = (page - 1) * _pageSize;
    if (start >= matches.length) return const <MusicTrack>[];
    return matches
        .skip(start)
        .take(_pageSize)
        .map(LocalMusicTrack.new)
        .toList(growable: false);
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
  void close() {}
}
