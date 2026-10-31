import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/sources/jamendo_service.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/sources/music_source.dart';

void main() {
  test(
    'source-prefixed IDs route stream lookup and preserve catalog results',
    () async {
      final source = _FakeSource();
      final repository = MusicRepository(sources: [source]);

      final tracks = await repository.search('ambient', page: 2);
      expect(tracks.single.sourceId, 'jamendo');
      expect(tracks.single.toSong().id, 'jamendo:42');
      expect(source.lastPage, 2);
      expect(
        await repository.getStreamUrl('jamendo:42'),
        source.track.streamUrl,
      );
      expect(repository.attributionFor(source.track), contains('Jamendo'));
    },
  );

  test('rejects malformed and unknown source IDs', () async {
    final repository = MusicRepository(sources: [_FakeSource()]);
    expect(() => repository.getStreamUrl('42'), throwsFormatException);
    expect(() => repository.getStreamUrl('unknown:42'), throwsStateError);
  });
}

class _FakeSource implements MusicSource {
  final track = JamendoTrack.fromMap({
    'id': '42',
    'name': 'Example',
    'artist_name': 'Artist',
    'audio': 'https://prod-1.storage.jamendo.com/?trackid=42',
    'audiodownload_allowed': false,
  });

  int? lastPage;

  @override
  String get id => 'jamendo';

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
  String attributionFor(MusicTrack track) => 'Music via Jamendo.';

  @override
  void close() {}
}
