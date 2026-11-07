import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/in_memory_library_repository.dart';
import 'package:nm_vibe/data/sources/local_files_source.dart';

void main() {
  test(
    'local search matches partial title and artist case-insensitively',
    () async {
      final library = InMemoryLibraryRepository(
        songs: [
          _song('title-match', title: 'Moonlight Sonata', artist: 'Ludwig'),
          _song(
            'artist-match',
            title: 'Piano Study',
            artist: 'Beyoncé Knowles',
          ),
          _song('unrelated', title: 'Evening Jazz', artist: 'Quartet'),
        ],
      );
      final source = LocalFilesMusicSource(library);
      addTearDown(library.close);

      final titleResults = await source.search(' moonL ', page: 1);
      final artistResults = await source.search('  BEYONCÉ   KNOW ', page: 1);
      final typoResults = await source.search('moonlght sonata', page: 1);

      expect(titleResults.map((track) => track.id), ['title-match']);
      expect(artistResults.map((track) => track.id), ['artist-match']);
      expect(typoResults.map((track) => track.id), ['title-match']);
    },
  );

  test('library updates invalidate the normalized query cache', () async {
    final library = InMemoryLibraryRepository(
      songs: [_song('first', title: 'Blue Train', artist: 'John Coltrane')],
    );
    final source = LocalFilesMusicSource(library);
    addTearDown(source.close);
    addTearDown(library.close);

    expect(await source.search('blue train', page: 1), hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await library.saveSongs([
      _song('second', title: 'Blue Train Live', artist: 'Another Artist'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await source.search('blue train', page: 1), hasLength(2));
  });
}

Song _song(String id, {required String title, required String artist}) => Song(
  id: id,
  filePath: 'C:/Music/$id.mp3',
  title: title,
  artist: artist,
  album: 'Test album',
  albumArtist: artist,
  duration: const Duration(minutes: 3),
  fileSize: 1,
  addedAt: DateTime(2026),
);
