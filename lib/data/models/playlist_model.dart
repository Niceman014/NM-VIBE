import 'song_model.dart';

/// A user-created playlist. Song order is the playlist order.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> songIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get length => songIds.length;

  Playlist copyWith({
    String? name,
    List<String>? songIds,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      songIds: songIds ?? this.songIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'songIds': songIds,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Playlist.fromMap(Map<Object?, Object?> map) {
    final rawIds = map['songIds'];
    final ids = <String>[];
    if (rawIds is List) {
      for (final id in rawIds) {
        if (id != null) ids.add(id.toString());
      }
    }
    int toMs(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return DateTime.now().millisecondsSinceEpoch;
    }

    return Playlist(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Playlist',
      songIds: ids,
      createdAt: DateTime.fromMillisecondsSinceEpoch(toMs(map['createdAt'])),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(toMs(map['updatedAt'])),
    );
  }
}

/// A playlist together with its resolved songs, ready to render.
class PlaylistWithSongs {
  const PlaylistWithSongs({required this.playlist, required this.songs});

  final Playlist playlist;
  final List<Song> songs;

  String get name => playlist.name;
  List<String> get songIds => playlist.songIds;
  int get length => songs.length;
  Duration get totalDuration =>
      songs.fold(Duration.zero, (total, song) => total + song.duration);
  String? get artworkKey {
    for (final song in songs) {
      if (song.hasArtwork) return song.artworkKey;
    }
    return null;
  }
}
