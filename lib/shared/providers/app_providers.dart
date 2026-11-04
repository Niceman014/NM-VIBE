import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:nm_vibe/data/models/playlist_model.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/features/player/controllers/player_controller.dart';
import 'package:nm_vibe/features/updates/controllers/update_controller.dart';
import 'package:nm_vibe/features/updates/services/update_strategy_factory.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/data/models/library_groups.dart';
import 'package:nm_vibe/core/audio/audio_handler.dart';
import 'package:nm_vibe/core/storage/settings_service.dart';

/// Overridden in `main()` with the real implementations.
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  throw UnimplementedError(
    'libraryRepositoryProvider must be overridden in main()',
  );
});

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
      throw UnimplementedError(
        'settingsControllerProvider must be overridden in main()',
      );
    });

final audioHandlerProvider = Provider<NmVibeAudioHandler>((ref) {
  throw UnimplementedError('audioHandlerProvider must be overridden in main()');
});

final updateControllerProvider =
    StateNotifierProvider<UpdateController, UpdateUiState>((ref) {
      final controller = UpdateController(
        UpdateStrategyFactory.forPlatform(
          UpdateStrategyFactory.currentPlatform,
        ),
      );
      return controller;
    });

final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlayerState>((ref) {
      final controller = PlayerController(
        handler: ref.watch(audioHandlerProvider),
        repository: ref.watch(libraryRepositoryProvider),
      );
      return controller;
    });

// ---------------------------------------------------------------- library data
final songsProvider = StreamProvider<List<Song>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchSongs();
});

final playlistsProvider = StreamProvider<List<Playlist>>((ref) {
  return ref.watch(libraryRepositoryProvider).watchPlaylists();
});

final lastScanTimeProvider = FutureProvider<DateTime?>((ref) {
  final repository = ref.watch(libraryRepositoryProvider);
  // Invalidate when the song list changes so the settings page refreshes.
  ref.watch(songsProvider);
  return repository.getLastScanTime();
});

List<Song> sortSongs(
  List<Song> songs,
  SongsSortMode mode, {
  bool ascending = true,
}) {
  final sorted = List<Song>.of(songs);
  int compare(Song a, Song b) {
    switch (mode) {
      case SongsSortMode.title:
        return a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        );
      case SongsSortMode.artist:
        final artistCompare = a.displayArtist.toLowerCase().compareTo(
          b.displayArtist.toLowerCase(),
        );
        if (artistCompare != 0) return artistCompare;
        return a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        );
      case SongsSortMode.album:
        final albumCompare = a.displayAlbum.toLowerCase().compareTo(
          b.displayAlbum.toLowerCase(),
        );
        if (albumCompare != 0) return albumCompare;
        final trackCompare = (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0);
        if (trackCompare != 0) return trackCompare;
        return a.displayTitle.toLowerCase().compareTo(
          b.displayTitle.toLowerCase(),
        );
      case SongsSortMode.dateAdded:
        return a.addedAt.compareTo(b.addedAt);
      case SongsSortMode.duration:
        return a.duration.compareTo(b.duration);
    }
  }

  sorted.sort(compare);
  if (!ascending) return sorted.reversed.toList(growable: false);
  return sorted;
}

final sortedSongsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(songsProvider).value ?? const <Song>[];
  final sortOptions = ref.watch(
    settingsControllerProvider.select(
      (settings) => (settings.songsSortMode, settings.songsSortAscending),
    ),
  );
  return sortSongs(songs, sortOptions.$1, ascending: sortOptions.$2);
});

final albumsProvider = Provider<List<AlbumGroup>>((ref) {
  return groupAlbums(ref.watch(sortedSongsProvider));
});

final artistsProvider = Provider<List<ArtistGroup>>((ref) {
  return groupArtists(ref.watch(sortedSongsProvider));
});

final favoriteSongsProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(sortedSongsProvider);
  return songs.where((song) => song.isFavorite).toList(growable: false);
});

final recentlyPlayedProvider = Provider<List<Song>>((ref) {
  final songs = ref.watch(songsProvider).value ?? const <Song>[];
  final played = songs.where((song) => song.lastPlayedAt != null).toList()
    ..sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
  return played;
});

/// Live search query used by the library search field.
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = Provider<List<Song>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return const <Song>[];
  final songs = ref.watch(sortedSongsProvider);
  return songs
      .where((song) {
        return song.displayTitle.toLowerCase().contains(query) ||
            song.displayArtist.toLowerCase().contains(query) ||
            song.displayAlbum.toLowerCase().contains(query);
      })
      .toList(growable: false);
});

final isLoadingLibraryProvider = Provider<bool>((ref) {
  return ref.watch(songsProvider).isLoading;
});

final libraryErrorProvider = Provider<Object?>((ref) {
  return ref.watch(songsProvider).error;
});

/// Looks up songs for a playlist, preserving playlist order.
List<Song> resolvePlaylistSongs(Playlist playlist, List<Song> library) {
  final byId = <String, Song>{for (final song in library) song.id: song};
  final resolved = <Song>[];
  for (final id in playlist.songIds) {
    final song = byId[id];
    if (song != null) resolved.add(song);
  }
  return resolved;
}

/// Default accent used while settings are unavailable (tests).
const int fallbackSeedColorValue = ThemeConstants.defaultSeedValue;
