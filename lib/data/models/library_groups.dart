import 'package:nm_vibe/data/models/song_model.dart';

/// Album as derived from the song collection. Not persisted.
class AlbumGroup {
  AlbumGroup({
    required this.key,
    required this.name,
    required this.artist,
    required this.songs,
    this.year,
  });

  final String key;
  final String name;
  final String artist;
  final List<Song> songs;
  final int? year;

  Duration get duration =>
      songs.fold(Duration.zero, (total, song) => total + song.duration);

  String? get artworkKey {
    for (final song in songs) {
      if (song.hasArtwork) return song.artworkKey;
    }
    return null;
  }

  Song get representative => songs.first;
}

/// Artist as derived from the song collection. Not persisted.
class ArtistGroup {
  ArtistGroup({
    required this.name,
    required this.songs,
    required this.albumKeys,
  });

  final String name;
  final List<Song> songs;
  final Set<String> albumKeys;

  int get albumCount => albumKeys.length;

  String? get artworkKey {
    for (final song in songs) {
      if (song.hasArtwork) return song.artworkKey;
    }
    return null;
  }
}

/// Groups songs into albums, ordering tracks by disc then track number.
List<AlbumGroup> groupAlbums(
  Iterable<Song> songs, {
  bool includeUnknown = true,
}) {
  final buckets = <String, List<Song>>{};
  for (final song in songs) {
    if (!includeUnknown && song.album.trim().isEmpty) continue;
    buckets.putIfAbsent(song.albumGroupKey, () => <Song>[]).add(song);
  }

  final albums = <AlbumGroup>[];
  for (final entry in buckets.entries) {
    final albumSongs = List<Song>.of(entry.value)
      ..sort((a, b) {
        final discCompare = (a.discNumber ?? 0).compareTo(b.discNumber ?? 0);
        if (discCompare != 0) return discCompare;
        final trackCompare = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
        if (trackCompare != 0) return trackCompare;
        return a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        );
      });
    final first = albumSongs.first;
    albums.add(
      AlbumGroup(
        key: entry.key,
        name: first.displayAlbum,
        artist: first.displayAlbumArtist,
        songs: albumSongs,
        year: first.year,
      ),
    );
  }

  albums.sort((a, b) {
    final artistCompare = a.artist.toLowerCase().compareTo(
      b.artist.toLowerCase(),
    );
    if (artistCompare != 0) return artistCompare;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return albums;
}

/// Groups songs by display artist.
List<ArtistGroup> groupArtists(Iterable<Song> songs) {
  final buckets = <String, List<Song>>{};
  for (final song in songs) {
    buckets.putIfAbsent(song.displayArtist, () => <Song>[]).add(song);
  }

  final artists = <ArtistGroup>[];
  for (final entry in buckets.entries) {
    final artistSongs = List<Song>.of(entry.value)
      ..sort(
        (a, b) => a.displayAlbum.toLowerCase().compareTo(
          b.displayAlbum.toLowerCase(),
        ),
      );
    artists.add(
      ArtistGroup(
        name: entry.key,
        songs: artistSongs,
        albumKeys: artistSongs.map((song) => song.albumGroupKey).toSet(),
      ),
    );
  }

  artists.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return artists;
}
