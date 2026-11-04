import 'dart:math' as math;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import 'package:nm_vibe/data/models/playlist_model.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/widgets/add_to_playlist_sheet.dart';
import 'package:nm_vibe/shared/widgets/empty_state.dart';
import 'package:nm_vibe/shared/widgets/playlist_artwork.dart';
import 'package:nm_vibe/shared/widgets/song_tile.dart';
import 'package:nm_vibe/shared/navigation/open_now_playing.dart';

/// Playlist detail: hero artwork, play/shuffle, drag-to-reorder tracks and
/// add/remove songs without leaving the page.
class PlaylistDetailPage extends ConsumerStatefulWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends ConsumerState<PlaylistDetailPage> {
  /// Optimistic local order so dragging feels instant while the write lands.
  List<String>? _localOrder;
  bool _savingOrder = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 800;
    final sidePadding = width >= 1000
        ? ((width - 960) / 2).clamp(24.0, 480.0)
        : (width >= 600 ? 24.0 : 16.0);

    final playlistsAsync = ref.watch(playlistsProvider);
    final songs = ref.watch(songsProvider).value ?? const <Song>[];
    final playlist = _findPlaylist(
      playlistsAsync.value ?? const <Playlist>[],
      widget.playlistId,
    );

    if (playlist == null) {
      if (playlistsAsync.isLoading) {
        return Scaffold(
          appBar: AppBar(backgroundColor: Colors.transparent),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return Scaffold(
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: const EmptyState(
          icon: Icons.queue_music_rounded,
          title: 'Playlist not found',
          message: 'It may have been deleted from another screen.',
        ),
      );
    }

    // Keep the optimistic order in sync with the database unless a reorder is
    // still being written (avoid snapping back mid-drag-save).
    if (!_savingOrder) {
      final stored = playlist.songIds;
      final local = _localOrder;
      if (local == null || !_listEquals(local, stored)) {
        _localOrder = List<String>.of(stored);
      }
    }
    final order = _localOrder ?? List<String>.of(playlist.songIds);
    final byId = <String, Song>{for (final song in songs) song.id: song};
    final orderedSongs = <Song>[
      for (final id in order)
        if (byId[id] != null) byId[id]!,
    ];
    final entry = PlaylistWithSongs(playlist: playlist, songs: orderedSongs);
    final player = ref.watch(playerControllerProvider);
    final currentSongId = player.current?.id;

    final hero = _buildHero(
      context: context,
      entry: entry,
      isWide: isWide,
      sidePadding: sidePadding,
      onPlay: () => _play(orderedSongs),
      onShuffle: () => _play(orderedSongs, shuffle: true),
      onAddSongs: () => _addSongs(playlist),
      onRename: () => _rename(playlist),
    );

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('Playlist', style: theme.textTheme.titleMedium),
        actions: [
          IconButton(
            tooltip: 'Rename playlist',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(playlist),
          ),
          IconButton(
            tooltip: 'Delete playlist',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _delete(playlist),
          ),
          const SizedBox(width: ThemeConstants.spacing4),
        ],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.alphaBlend(
                scheme.primaryContainer.withValues(alpha: 0.45),
                scheme.surface,
              ),
              scheme.surface,
            ],
            stops: const [0, 0.4],
          ),
        ),
        child: orderedSongs.isEmpty
            ? ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  hero,
                  EmptyState(
                    icon: Icons.playlist_add_rounded,
                    title: 'A blank canvas',
                    message: 'Add songs from your library and arrange them exactly how you want.',
                    action: FilledButton.icon(
                      onPressed: () => _addSongs(playlist),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add songs'),
                    ),
                  ),
                ],
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.only(bottom: 120),
                header: hero,
                buildDefaultDragHandles: false,
                itemCount: orderedSongs.length,
                onReorder: (oldIndex, newIndex) =>
                    _onReorder(oldIndex, newIndex, playlist, orderedSongs),
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, _) {
                      return Material(
                        elevation: 2 + animation.value * 8,
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        child: child,
                      );
                    },
                  );
                },
                itemBuilder: (context, index) {
                  final song = orderedSongs[index];
                  return Padding(
                    key: ValueKey<String>(song.id),
                    padding: EdgeInsets.symmetric(
                      horizontal: math.max(
                        0.0,
                        sidePadding - ThemeConstants.spacing8,
                      ),
                    ),
                    child: SongTile(
                      song: song,
                      isCurrent: song.id == currentSongId,
                      isPlaying: player.playing,
                      subtitle: song.displayAlbum,
                      onTap: () {
                        unawaited(
                          playSongsAndOpen(
                            context,
                            ref,
                            orderedSongs,
                            initialIndex: index,
                          ),
                        );
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatDuration(song.duration),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove from playlist',
                            iconSize: 20,
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                            ),
                            onPressed: () => _removeSong(playlist, song),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: ThemeConstants.spacing8,
                              ),
                              child: Icon(
                                Icons.drag_handle_rounded,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildHero({
    required BuildContext context,
    required PlaylistWithSongs entry,
    required bool isWide,
    required double sidePadding,
    required VoidCallback onPlay,
    required VoidCallback onShuffle,
    required VoidCallback onAddSongs,
    required VoidCallback onRename,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = Column(
      crossAxisAlignment: isWide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          'PLAYLIST',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: isWide
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                entry.name,
                textAlign: isWide ? TextAlign.start : TextAlign.center,
                style: isWide
                    ? theme.textTheme.displaySmall?.copyWith(fontSize: 40)
                    : theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Rename playlist',
              iconSize: 20,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onRename,
            ),
          ],
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Text(
          entry.songs.isEmpty
              ? 'No songs yet'
              : '${trackCountLabel(entry.songs.length)} · ${formatTotalDuration(entry.totalDuration)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing24),
        Wrap(
          spacing: ThemeConstants.spacing12,
          runSpacing: ThemeConstants.spacing12,
          alignment: isWide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: entry.songs.isEmpty ? null : onPlay,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play'),
            ),
            FilledButton.tonalIcon(
              onPressed: entry.songs.isEmpty ? null : onShuffle,
              icon: const Icon(Icons.shuffle_rounded),
              label: const Text('Shuffle'),
            ),
            OutlinedButton.icon(
              onPressed: onAddSongs,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add songs'),
            ),
          ],
        ),
      ],
    );

    final artSize = isWide
        ? 232.0
        : math.min(MediaQuery.sizeOf(context).width * 0.46, 190.0);
    final art = PlaylistArtwork(
      songs: entry.songs,
      size: artSize,
      borderRadius: ThemeConstants.radiusLarge,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePadding,
        ThemeConstants.spacing4,
        sidePadding,
        ThemeConstants.spacing16,
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                art,
                const SizedBox(width: ThemeConstants.spacing32),
                Expanded(child: meta),
              ],
            )
          : Column(
              children: [
                const SizedBox(height: ThemeConstants.spacing8),
                art,
                const SizedBox(height: ThemeConstants.spacing24),
                meta,
              ],
            ),
    );
  }

  // -------------------------------------------------------------- interactions
  Future<void> _play(List<Song> songs, {bool shuffle = false}) async {
    if (songs.isEmpty) return;
    final queue = List<Song>.of(songs);
    if (shuffle) queue.shuffle(math.Random());
    final controller = ref.read(playerControllerProvider.notifier);
    final state = ref.read(playerControllerProvider);
    if (shuffle != state.shuffleEnabled) {
      await controller.toggleShuffle();
    }
    if (!mounted) return;
    await playSongsAndOpen(context, ref, queue);
  }

  Future<void> _addSongs(Playlist playlist) async {
    await showSongPickerSheet(
      context,
      ref,
      playlist: playlist,
      existingSongIds: playlist.songIds,
    );
  }

  Future<void> _rename(Playlist playlist) async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Rename playlist',
      initialName: playlist.name,
      confirmLabel: 'Save',
    );
    if (!mounted ||
        name == null ||
        name.trim().isEmpty ||
        name.trim() == playlist.name) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .updatePlaylist(
            playlist.copyWith(
              name: name.trim(),
              songIds: List<String>.of(_localOrder ?? playlist.songIds),
            ),
          );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not rename playlist: $error')),
      );
    }
  }

  Future<void> _delete(Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          '“${playlist.name}” will be removed. Your songs stay in the library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(libraryRepositoryProvider).deletePlaylist(playlist.id);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Deleted “${playlist.name}”')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not delete playlist: $error')),
      );
    }
  }

  Future<void> _removeSong(Playlist playlist, Song song) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .removeSongFromPlaylist(playlist.id, song.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Removed “${song.displayTitle}”')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not remove song: $error')),
      );
    }
  }

  Future<void> _onReorder(
    int oldIndex,
    int newIndex,
    Playlist playlist,
    List<Song> visibleSongs,
  ) async {
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= visibleSongs.length || target == oldIndex) {
      return;
    }
    final reordered = List<Song>.of(visibleSongs);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(target, moved);
    final visibleIds = reordered.map((song) => song.id).toSet();
    final newOrder = <String>[
      ...reordered.map((song) => song.id),
      // Preserve ids that are not in the library right now (missing files).
      ...?_localOrder?.where((id) => !visibleIds.contains(id)),
    ];
    setState(() {
      _localOrder = newOrder;
      _savingOrder = true;
    });
    try {
      await ref
          .read(libraryRepositoryProvider)
          .reorderPlaylistSongs(playlist.id, newOrder);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the new order: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  static Playlist? _findPlaylist(List<Playlist> playlists, String id) {
    for (final playlist in playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
