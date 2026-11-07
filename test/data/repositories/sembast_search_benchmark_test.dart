import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sembast/sembast.dart';

import 'package:nm_vibe/core/storage/db_service.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/data/repositories/music_search_ranking.dart';
import 'package:nm_vibe/data/sources/local_files_source.dart';
import 'package:nm_vibe/data/sources/music_source.dart';

void main() {
  test('profiles local search on isolated on-disk Sembast catalogs', () async {
    for (final count in [100, 1000, 5000, 10000]) {
      final directory = await Directory.systemTemp.createTemp(
        'nm_vibe_search_benchmark_',
      );
      final database = await AppDatabase.open(
        overridePath: p.join(directory.path, 'catalog.db'),
      );
      final library = SembastLibraryRepository(database);
      await library.init();
      final source = LocalFilesMusicSource(library);
      try {
        await library.saveSongs(
          List.generate(count, (index) => _song(index, count)),
        );

        final store = stringMapStoreFactory.store('songs');
        final readWatch = Stopwatch()..start();
        final snapshots = await store.find(database.database);
        readWatch.stop();

        final decodeWatch = Stopwatch()..start();
        final decoded = snapshots
            .map((snapshot) => Song.fromMap(snapshot.value))
            .toList(growable: false);
        decodeWatch.stop();

        final sortWatch = Stopwatch()..start();
        final sorted = List<Song>.of(decoded)
          ..sort(
            (a, b) => a.displayTitle.toLowerCase().compareTo(
              b.displayTitle.toLowerCase(),
            ),
          );
        sortWatch.stop();

        final normalizationWatch = Stopwatch()..start();
        for (final song in decoded) {
          normalizeMusicSearchText(song.displayTitle);
          normalizeMusicSearchText(song.displayArtist);
          normalizeMusicSearchText(song.displayAlbum);
        }
        normalizationWatch.stop();

        final repositoryWatch = Stopwatch()..start();
        final repositorySongs = await library.getSongs();
        repositoryWatch.stop();

        final exactWatch = Stopwatch()..start();
        final exact = await source.search('moonlight sonata', page: 1);
        exactWatch.stop();

        final titleWatch = Stopwatch()..start();
        final partialTitle = await source.search('track 1', page: 1);
        titleWatch.stop();

        final artistWatch = Stopwatch()..start();
        final artist = await source.search('artist 1', page: 1);
        artistWatch.stop();

        final repeatedWatch = Stopwatch()..start();
        final repeated = await source.search('artist 1', page: 1);
        repeatedWatch.stop();

        expect(snapshots, hasLength(count));
        expect(sorted, hasLength(count));
        expect(repositorySongs, hasLength(count));
        expect(exact, hasLength(1));
        expect(partialTitle, isNotEmpty);
        expect(artist, isNotEmpty);
        expect(
          repeated.map((track) => track.id),
          artist.map((track) => track.id),
        );

        final changedSong = repositorySongs.first;
        final invalidationWatch = Stopwatch()..start();
        await library.updateSong(
          changedSong.copyWith(title: 'Sembast Invalidation Marker'),
        );
        var invalidated = const <MusicTrack>[];
        while (invalidationWatch.elapsed < const Duration(seconds: 2)) {
          invalidated = await source.search(
            'sembast invalidation marker',
            page: 1,
          );
          if (invalidated.any((track) => track.id == changedSong.id)) break;
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
        invalidationWatch.stop();
        expect(invalidated.map((track) => track.id), contains(changedSong.id));

        // This standalone process RSS includes the Flutter test runner and is
        // not a reliable per-index memory measurement, so it is not reported.
        // ignore: avoid_print
        print(
          'Sembast disk $count: rawRead=${readWatch.elapsedMilliseconds}ms '
          'decode=${decodeWatch.elapsedMilliseconds}ms '
          'sort=${sortWatch.elapsedMilliseconds}ms '
          'normalizeIndexFields=${normalizationWatch.elapsedMilliseconds}ms '
          'repoGetSongs=${repositoryWatch.elapsedMilliseconds}ms '
          'firstSearch+index=${exactWatch.elapsedMilliseconds}ms '
          'partialTitle=${titleWatch.elapsedMilliseconds}ms '
          'artist=${artistWatch.elapsedMilliseconds}ms '
          'repeat=${repeatedWatch.elapsedMicroseconds}us '
          'update-to-refreshed-search=${invalidationWatch.elapsedMilliseconds}ms',
        );
      } finally {
        source.close();
        await library.close();
        await directory.delete(recursive: true);
      }
    }
  });
}

Song _song(int index, int count) {
  final target = index == count - 1;
  return Song(
    id: 'sembast-$index',
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
