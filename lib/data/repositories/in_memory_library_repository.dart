import 'dart:async';

import 'package:nm_vibe/data/models/playlist_model.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'library_repository.dart';

/// Non-persistent repository used by widget tests and screenshot demos.
class InMemoryLibraryRepository implements LibraryRepository {
  InMemoryLibraryRepository({Iterable<Song> songs = const []}) {
    for (final song in songs) {
      _songs[song.id] = song;
    }
    _emitSongs();
    _emitPlaylists();
  }

  final Map<String, Song> _songs = <String, Song>{};
  final Map<String, Playlist> _playlists = <String, Playlist>{};

  final StreamController<List<Song>> _songController =
      StreamController<List<Song>>.broadcast();
  final StreamController<List<Playlist>> _playlistController =
      StreamController<List<Playlist>>.broadcast();

  DateTime? _lastScanTime;
  List<Song> _songsSnapshot = const [];

  void _emitSongs() {
    _songsSnapshot = _songs.values.toList()
      ..sort(
        (a, b) => a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        ),
      );
    if (!_songController.isClosed) _songController.add(_songsSnapshot);
  }

  void _emitPlaylists() {
    final playlists = _playlists.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!_playlistController.isClosed) _playlistController.add(playlists);
  }

  @override
  Future<void> init() async {}

  @override
  Future<List<Song>> getSongs() async => List<Song>.of(_songsSnapshot);

  @override
  Stream<List<Song>> watchSongs() async* {
    yield _songsSnapshot;
    yield* _songController.stream;
  }

  @override
  Future<Song?> getSong(String id) async => _songs[id];

  @override
  Future<void> saveSongs(Iterable<Song> songs) async {
    for (final song in songs) {
      _songs[song.id] = song;
    }
    _emitSongs();
  }

  @override
  Future<void> updateSong(Song song) async {
    _songs[song.id] = song;
    _emitSongs();
  }

  @override
  Future<void> deleteSongs(Iterable<String> ids) async {
    for (final id in ids) {
      _songs.remove(id);
    }
    _emitSongs();
  }

  @override
  Future<void> deleteSongsNotIn(Set<String> keepIds) async {
    _songs.removeWhere((id, _) => !keepIds.contains(id));
    _emitSongs();
  }

  @override
  Future<void> clearSongs() async {
    _songs.clear();
    _emitSongs();
  }

  @override
  Future<void> toggleFavorite(String songId) async {
    final song = _songs[songId];
    if (song == null) return;
    await updateSong(song.copyWith(isFavorite: !song.isFavorite));
  }

  @override
  Future<void> recordPlay(String songId) async {
    final song = _songs[songId];
    if (song == null) return;
    await updateSong(
      song.copyWith(
        playCount: song.playCount + 1,
        lastPlayedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> updatePlaybackInfo(String songId, Duration duration) async {
    final song = _songs[songId];
    if (song == null || duration <= Duration.zero) return;
    await updateSong(song.copyWith(duration: duration));
  }

  @override
  Future<List<Playlist>> getPlaylists() async =>
      _playlists.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Stream<List<Playlist>> watchPlaylists() async* {
    yield await getPlaylists();
    yield* _playlistController.stream;
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
    _playlists[playlist.id] = playlist;
    _emitPlaylists();
    return playlist;
  }

  @override
  Future<void> updatePlaylist(Playlist playlist) async {
    _playlists[playlist.id] = playlist.copyWith(updatedAt: DateTime.now());
    _emitPlaylists();
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _playlists.remove(playlistId);
    _emitPlaylists();
  }

  @override
  Future<void> addSongsToPlaylist(
    String playlistId,
    List<String> songIds,
  ) async {
    final playlist = _playlists[playlistId];
    if (playlist == null) return;
    final updated = <String>[...playlist.songIds];
    for (final id in songIds) {
      if (!updated.contains(id)) updated.add(id);
    }
    await updatePlaylist(playlist.copyWith(songIds: updated));
  }

  @override
  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final playlist = _playlists[playlistId];
    if (playlist == null) return;
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
    final playlist = _playlists[playlistId];
    if (playlist == null) return;
    await updatePlaylist(playlist.copyWith(songIds: List<String>.of(songIds)));
  }

  @override
  Future<DateTime?> getLastScanTime() async => _lastScanTime;

  @override
  Future<void> setLastScanTime(DateTime time) async {
    _lastScanTime = time;
  }

  @override
  Future<void> close() async {
    await _songController.close();
    await _playlistController.close();
  }
}
