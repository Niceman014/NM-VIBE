import 'package:sembast/sembast.dart';

import 'package:nm_vibe/data/models/playlist_model.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/models/library_groups.dart';
import 'package:nm_vibe/core/storage/db_service.dart';
import 'package:nm_vibe/core/utils/logger.dart';

/// Persistence boundary for the local music library.
///
/// Everything the app knows about songs and playlists goes through this
/// interface, which keeps a future online/sync source easy to add without
/// touching the UI.
abstract class LibraryRepository {
  Future<void> init();

  // ------------------------------------------------------------------ songs
  Future<List<Song>> getSongs();
  Stream<List<Song>> watchSongs();
  Future<Song?> getSong(String id);
  Future<void> saveSongs(Iterable<Song> songs);
  Future<void> updateSong(Song song);
  Future<void> deleteSongs(Iterable<String> ids);
  Future<void> deleteSongsNotIn(Set<String> keepIds);
  Future<void> clearSongs();
  Future<void> toggleFavorite(String songId);
  Future<void> recordPlay(String songId);
  Future<void> updatePlaybackInfo(String songId, Duration duration);

  // -------------------------------------------------------------- playlists
  Future<List<Playlist>> getPlaylists();
  Stream<List<Playlist>> watchPlaylists();
  Future<Playlist> createPlaylist(
    String name, {
    List<String> songIds = const [],
  });
  Future<void> updatePlaylist(Playlist playlist);
  Future<void> deletePlaylist(String playlistId);
  Future<void> addSongsToPlaylist(String playlistId, List<String> songIds);
  Future<void> removeSongFromPlaylist(String playlistId, String songId);
  Future<void> reorderPlaylistSongs(String playlistId, List<String> songIds);

  // ------------------------------------------------------------------- meta
  Future<DateTime?> getLastScanTime();
  Future<void> setLastScanTime(DateTime time);
  Future<void> close();
}

/// sembast-backed implementation used by the running app.
class SembastLibraryRepository implements LibraryRepository {
  SembastLibraryRepository(this._appDatabase);

  static const AppLogger _log = AppLogger('LibraryRepository');
  static final StoreRef<String, Map<String, Object?>> _songs =
      stringMapStoreFactory.store('songs');
  static final StoreRef<String, Map<String, Object?>> _playlists =
      stringMapStoreFactory.store('playlists');
  static final StoreRef<String, Map<String, Object?>> _meta =
      StoreRef<String, Map<String, Object?>>('meta');

  final AppDatabase _appDatabase;

  Database get _db => _appDatabase.database;

  static Future<SembastLibraryRepository> open() async {
    final repository = SembastLibraryRepository(await AppDatabase.open());
    await repository.init();
    return repository;
  }

  static Future<SembastLibraryRepository> openInMemory() async {
    final repository = SembastLibraryRepository(
      await AppDatabase.openInMemory(),
    );
    await repository.init();
    return repository;
  }

  @override
  Future<void> init() async {
    // Touch the stores so the file is created eagerly.
    await _songs.find(_db);
    await _playlists.find(_db);
    _log.d('Library repository ready at ${_appDatabase.path}');
  }

  // ------------------------------------------------------------------ songs
  @override
  Future<List<Song>> getSongs() async {
    final snapshots = await _songs.find(_db);
    return _toSongs(snapshots);
  }

  @override
  Stream<List<Song>> watchSongs() {
    return _songs.query().onSnapshots(_db).map(_toSongs);
  }

  @override
  Future<Song?> getSong(String id) async {
    final value = await _songs.record(id).get(_db);
    if (value == null) return null;
    return Song.fromMap(value);
  }

  @override
  Future<void> saveSongs(Iterable<Song> songs) async {
    final list = songs.toList(growable: false);
    if (list.isEmpty) return;
    await _db.transaction((txn) async {
      for (final song in list) {
        await _songs.record(song.id).put(txn, song.toMap());
      }
    });
    _log.d('Saved ${list.length} songs');
  }

  @override
  Future<void> updateSong(Song song) async {
    await _songs.record(song.id).put(_db, song.toMap());
  }

  @override
  Future<void> deleteSongs(Iterable<String> ids) async {
    final list = ids.toList(growable: false);
    if (list.isEmpty) return;
    await _db.transaction((txn) async {
      for (final id in list) {
        await _songs.record(id).delete(txn);
      }
    });
  }

  @override
  Future<void> deleteSongsNotIn(Set<String> keepIds) async {
    final snapshots = await _songs.find(_db);
    final stale = <String>[
      for (final snapshot in snapshots)
        if (!keepIds.contains(snapshot.key)) snapshot.key,
    ];
    await deleteSongs(stale);
  }

  @override
  Future<void> clearSongs() async {
    await _songs.delete(_db);
  }

  @override
  Future<void> toggleFavorite(String songId) async {
    final value = await _songs.record(songId).get(_db);
    if (value == null) return;
    final song = Song.fromMap(value);
    await updateSong(song.copyWith(isFavorite: !song.isFavorite));
  }

  @override
  Future<void> recordPlay(String songId) async {
    final value = await _songs.record(songId).get(_db);
    if (value == null) return;
    final song = Song.fromMap(value);
    await updateSong(
      song.copyWith(
        playCount: song.playCount + 1,
        lastPlayedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updatePlaybackInfo(String songId, Duration duration) async {
    final value = await _songs.record(songId).get(_db);
    if (value == null) return;
    final song = Song.fromMap(value);
    if (duration > Duration.zero && duration != song.duration) {
      await updateSong(song.copyWith(duration: duration));
    }
  }

  // -------------------------------------------------------------- playlists
  @override
  Future<List<Playlist>> getPlaylists() async {
    final snapshots = await _playlists.find(_db);
    return _toPlaylists(snapshots);
  }

  @override
  Stream<List<Playlist>> watchPlaylists() {
    return _playlists.query().onSnapshots(_db).map(_toPlaylists);
  }

  @override
  Future<Playlist> createPlaylist(
    String name, {
    List<String> songIds = const [],
  }) async {
    final now = DateTime.now();
    final playlist = Playlist(
      id: 'pl_${now.microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'New playlist' : name.trim(),
      songIds: List<String>.of(songIds),
      createdAt: now,
      updatedAt: now,
    );
    await _playlists.record(playlist.id).put(_db, playlist.toMap());
    return playlist;
  }

  @override
  Future<void> updatePlaylist(Playlist playlist) async {
    await _playlists
        .record(playlist.id)
        .put(_db, playlist.copyWith(updatedAt: DateTime.now()).toMap());
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _playlists.record(playlistId).delete(_db);
  }

  @override
  Future<void> addSongsToPlaylist(
    String playlistId,
    List<String> songIds,
  ) async {
    final value = await _playlists.record(playlistId).get(_db);
    if (value == null) return;
    final playlist = Playlist.fromMap(value);
    final updated = <String>[...playlist.songIds];
    for (final id in songIds) {
      if (!updated.contains(id)) updated.add(id);
    }
    await updatePlaylist(playlist.copyWith(songIds: updated));
  }

  @override
  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final value = await _playlists.record(playlistId).get(_db);
    if (value == null) return;
    final playlist = Playlist.fromMap(value);
    await updatePlaylist(
      playlist.copyWith(
        songIds: playlist.songIds.where((id) => id != songId).toList(),
      ),
    );
  }

  @override
  Future<void> reorderPlaylistSongs(
    String playlistId,
    List<String> songIds,
  ) async {
    final value = await _playlists.record(playlistId).get(_db);
    if (value == null) return;
    final playlist = Playlist.fromMap(value);
    await updatePlaylist(playlist.copyWith(songIds: List<String>.of(songIds)));
  }

  // ------------------------------------------------------------------- meta
  @override
  Future<DateTime?> getLastScanTime() async {
    final value = await _meta.record('lastScan').get(_db);
    final at = value?['at'];
    if (at is int) return DateTime.fromMillisecondsSinceEpoch(at);
    return null;
  }

  @override
  Future<void> setLastScanTime(DateTime time) async {
    await _meta.record('lastScan').put(_db, {
      'at': time.millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> close() => _appDatabase.close();

  List<Song> _toSongs(
    List<RecordSnapshot<String, Map<String, Object?>>> snapshots,
  ) {
    final songs = snapshots
        .map((snapshot) => Song.fromMap(snapshot.value))
        .toList();
    songs.sort(
      (a, b) =>
          a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
    );
    return songs;
  }

  List<Playlist> _toPlaylists(
    List<RecordSnapshot<String, Map<String, Object?>>> snapshots,
  ) {
    final playlists = snapshots
        .map((snapshot) => Playlist.fromMap(snapshot.value))
        .toList();
    playlists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return playlists;
  }
}

/// Groups songs for the albums/artists tabs.
List<AlbumGroup> albumsFrom(List<Song> songs) => groupAlbums(songs);

List<ArtistGroup> artistsFrom(List<Song> songs) => groupArtists(songs);
