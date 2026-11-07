import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/in_memory_library_repository.dart';
import 'package:nm_vibe/data/sources/local_files_source.dart';

void main() {
  test('synthetic local search benchmark at 1k, 5k and 10k tracks', () async {
    for (final count in [1000, 5000, 10000]) {
      final library = InMemoryLibraryRepository(
        songs: List.generate(count, (index) => _song(index, count)),
      );
      final source = LocalFilesMusicSource(library);
      final legacyWatch = Stopwatch()..start();
      final legacyMatches = await _legacySearch(library, 'artist 1');
      legacyWatch.stop();
      final firstWatch = Stopwatch()..start();
      final first = await source.search('moonlight sonata', page: 1);
      firstWatch.stop();
      final partialTitleWatch = Stopwatch()..start();
      final partialTitle = await source.search('track 1', page: 1);
      partialTitleWatch.stop();
      final partialArtistWatch = Stopwatch()..start();
      final partialArtist = await source.search('artist 1', page: 1);
      partialArtistWatch.stop();
      final repeatWatch = Stopwatch()..start();
      final repeated = await source.search('artist 1', page: 1);
      repeatWatch.stop();

      expect(first, isNotEmpty);
      expect(partialTitle, isNotEmpty);
      expect(partialArtist, isNotEmpty);
      expect(legacyMatches, isNotEmpty);
      expect(
        partialArtist.map((track) => track.id),
        repeated.map((track) => track.id),
      );
      // This is a runnable synthetic benchmark, so stdout is its result channel.
      // ignore: avoid_print
      print(
        'Synthetic $count tracks: legacy-full-scan=${legacyWatch.elapsedMicroseconds}us, '
        'indexed-exact/index-build=${firstWatch.elapsedMicroseconds}us, '
        'partial-title=${partialTitleWatch.elapsedMicroseconds}us, '
        'partial-artist=${partialArtistWatch.elapsedMicroseconds}us, '
        'repeat-artist=${repeatWatch.elapsedMicroseconds}us',
      );
      source.close();
      await library.close();
    }
    // Dart VM RSS includes the test runner and allocator; it is not a reliable
    // per-index memory measurement, so this benchmark intentionally omits it.
  });
}

Future<List<Song>> _legacySearch(
  InMemoryLibraryRepository library,
  String query,
) async {
  final normalized = query.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  final songs = await library.getSongs();
  return songs
      .where((song) {
        String normalize(String value) =>
            value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
        return normalize(song.displayTitle).contains(normalized) ||
            normalize(song.displayArtist).contains(normalized) ||
            normalize(song.displayAlbum).contains(normalized);
      })
      .toList(growable: false);
}

Song _song(int index, int count) {
  final target = index == count - 1;
  return Song(
    id: 'synthetic-$index',
    filePath: 'C:/Synthetic/$index.mp3',
    title: target ? 'Moonlight Sonata' : 'Synthetic Track $index',
    artist: target ? 'Ludwig van Beethoven' : 'Artist ${index % 700}',
    album: 'Synthetic Album ${index % 400}',
    albumArtist: 'Artist ${index % 700}',
    duration: const Duration(minutes: 3),
    fileSize: 1000,
    addedAt: DateTime(2026).add(Duration(seconds: index)),
  );
}
