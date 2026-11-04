import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import 'package:nm_vibe/data/models/playlist_model.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/widgets/add_to_playlist_sheet.dart';
import 'package:nm_vibe/shared/widgets/empty_state.dart';
import 'package:nm_vibe/shared/widgets/loading_skeleton.dart';
import 'package:nm_vibe/shared/widgets/playlist_artwork.dart';
import 'playlist_detail_page.dart';

enum _PlaylistMenuAction { rename, delete }

/// Playlists overview: a responsive grid of artwork-forward playlist cards.
class PlaylistsPage extends ConsumerWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final sidePadding = width >= 1000
        ? ((width - 960) / 2).clamp(24.0, 480.0)
        : (width >= 600 ? 24.0 : 16.0);

    final playlistsAsync = ref.watch(playlistsProvider);
    final playlists = playlistsAsync.value ?? const <Playlist>[];
    final songs = ref.watch(songsProvider).value ?? const <Song>[];
    final entries = [
      for (final playlist in playlists)
        PlaylistWithSongs(
          playlist: playlist,
          songs: resolvePlaylistSongs(playlist, songs),
        ),
    ];
    final totalSongs = entries.fold<int>(
      0,
      (total, entry) => total + entry.length,
    );
    final loading = playlistsAsync.isLoading && playlists.isEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                sidePadding,
                ThemeConstants.spacing8,
                sidePadding,
                ThemeConstants.spacing8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COLLECTIONS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 2.6,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: ThemeConstants.spacing8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Playlists',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                            const SizedBox(height: ThemeConstants.spacing8),
                            Text(
                              playlists.isEmpty
                                  ? 'Group the songs you love.'
                                  : '${playlists.length} ${playlists.length == 1 ? 'playlist' : 'playlists'} · $totalSongs songs',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: ThemeConstants.spacing12),
                      width >= 480
                          ? FilledButton.tonalIcon(
                              onPressed: () => _createPlaylist(context, ref),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('New playlist'),
                            )
                          : IconButton.filledTonal(
                              tooltip: 'New playlist',
                              onPressed: () => _createPlaylist(context, ref),
                              icon: const Icon(Icons.add_rounded),
                            ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (playlistsAsync.hasError)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load playlists',
                message: 'Check your library storage and try again.',
                action: FilledButton.icon(
                  onPressed: () => ref.invalidate(playlistsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ),
            )
          else if (loading)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  sidePadding,
                  ThemeConstants.spacing8,
                  sidePadding,
                  0,
                ),
                child: const SkeletonCollectionGrid(count: 6),
              ),
            )
          else if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.queue_music_rounded,
                title: 'No playlists yet',
                message:
                    'Create a playlist for a mood, a road trip or that one '
                    'album you keep replaying.',
                action: FilledButton.icon(
                  onPressed: () => _createPlaylist(context, ref),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create playlist'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                sidePadding,
                ThemeConstants.spacing8,
                sidePadding,
                0,
              ),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  crossAxisSpacing: ThemeConstants.spacing16,
                  mainAxisSpacing: ThemeConstants.spacing16,
                  childAspectRatio: 0.72,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final entry = entries[index];
                  return _PlaylistCard(
                    entry: entry,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            PlaylistDetailPage(playlistId: entry.playlist.id),
                      ),
                    ),
                    onRename: () =>
                        _renamePlaylist(context, ref, entry.playlist),
                    onDelete: () =>
                        _deletePlaylist(context, ref, entry.playlist),
                  );
                }, childCount: entries.length),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final name = await showPlaylistNameDialog(context);
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(libraryRepositoryProvider).createPlaylist(name.trim());
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Created “${name.trim()}”')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create playlist: $error')),
      );
    }
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Rename playlist',
      initialName: playlist.name,
      confirmLabel: 'Save',
    );
    if (name == null || name.trim().isEmpty || name.trim() == playlist.name) {
      return;
    }
    try {
      await ref
          .read(libraryRepositoryProvider)
          .updatePlaylist(playlist.copyWith(name: name.trim()));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not rename playlist: $error')),
      );
    }
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          '“${playlist.name}” will be removed. Your songs stay safe in the library.',
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
    if (confirmed != true) return;
    try {
      await ref.read(libraryRepositoryProvider).deletePlaylist(playlist.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deleted “${playlist.name}”')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete playlist: $error')),
      );
    }
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.entry,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final PlaylistWithSongs entry;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacing8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.maxWidth;
                  return Stack(
                    children: [
                      PlaylistArtwork(
                        songs: entry.songs,
                        size: side,
                        borderRadius: ThemeConstants.radiusMedium,
                      ),
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ThemeConstants.spacing8,
                            vertical: ThemeConstants.spacing4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh.withValues(
                              alpha: 0.92,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.queue_music_rounded,
                                size: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: ThemeConstants.spacing4),
                              Text(
                                '${entry.length}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: _CardMenuButton(
                          onRename: onRename,
                          onDelete: onDelete,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ThemeConstants.spacing4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacing4),
                    Text(
                      entry.length == 0
                          ? 'Empty playlist'
                          : '${trackCountLabel(entry.length)} · ${formatTotalDuration(entry.totalDuration)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardMenuButton extends StatelessWidget {
  const _CardMenuButton({required this.onRename, required this.onDelete});

  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: PopupMenuButton<_PlaylistMenuAction>(
        tooltip: 'Playlist options',
        icon: const Icon(Icons.more_horiz_rounded, size: 18),
        iconSize: 18,
        padding: const EdgeInsets.all(ThemeConstants.spacing8),
        position: PopupMenuPosition.under,
        onSelected: (action) {
          switch (action) {
            case _PlaylistMenuAction.rename:
              onRename();
            case _PlaylistMenuAction.delete:
              onDelete();
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: _PlaylistMenuAction.rename,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 20),
                SizedBox(width: ThemeConstants.spacing12),
                Text('Rename'),
              ],
            ),
          ),
          PopupMenuItem(
            value: _PlaylistMenuAction.delete,
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 20),
                SizedBox(width: ThemeConstants.spacing12),
                Text('Delete'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
