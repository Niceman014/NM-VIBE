import 'package:flutter/material.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/widgets/add_to_playlist_sheet.dart';

/// Presentation variants for the per-song overflow button.
enum SongActionsVariant { tile, header, card }

enum _SongAction { playNext, addToQueue, addToPlaylist, toggleFavorite, info }

/// Overflow menu shared by every song row in the app.
///
/// The heavy lifting lives here so rows and pages stay declarative.
class SongActionsButton extends ConsumerWidget {
  const SongActionsButton({
    super.key,
    required this.song,
    this.variant = SongActionsVariant.tile,
  });

  final Song song;
  final SongActionsVariant variant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final icon = Icon(
      Icons.more_vert,
      size: variant == SongActionsVariant.header ? 22 : 20,
      color: scheme.onSurfaceVariant,
    );

    return PopupMenuButton<_SongAction>(
      tooltip: 'Song options',
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      onSelected: (action) => _handle(context, ref, action),
      itemBuilder: (context) {
        final theme = Theme.of(context);
        PopupMenuEntry<_SongAction> item(
          _SongAction value,
          IconData iconData,
          String label,
        ) {
          return PopupMenuItem<_SongAction>(
            value: value,
            child: Row(
              children: [
                Icon(
                  iconData,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: ThemeConstants.spacing12),
                Text(label),
              ],
            ),
          );
        }

        return [
          item(_SongAction.playNext, Icons.skip_next_rounded, 'Play next'),
          item(
            _SongAction.addToQueue,
            Icons.queue_music_rounded,
            'Add to queue',
          ),
          item(
            _SongAction.addToPlaylist,
            Icons.playlist_add_rounded,
            'Add to playlist',
          ),
          item(
            _SongAction.toggleFavorite,
            song.isFavorite
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            song.isFavorite ? 'Remove from favourites' : 'Add to favourites',
          ),
          const PopupMenuDivider(),
          item(_SongAction.info, Icons.info_outline_rounded, 'Song info'),
        ];
      },
      child: variant == SongActionsVariant.header
          ? Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeConstants.spacing8,
                vertical: ThemeConstants.spacing8,
              ),
              child: icon,
            )
          : Padding(
              padding: const EdgeInsets.all(ThemeConstants.spacing8),
              child: icon,
            ),
    );
  }

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    _SongAction action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(playerControllerProvider.notifier);
    switch (action) {
      case _SongAction.playNext:
        await controller.playNext(song);
        messenger.showSnackBar(
          SnackBar(content: Text('“${song.displayTitle}” plays next')),
        );
      case _SongAction.addToQueue:
        await controller.addToQueue(song);
        messenger.showSnackBar(
          SnackBar(content: Text('“${song.displayTitle}” added to queue')),
        );
      case _SongAction.addToPlaylist:
        await showAddToPlaylistSheet(context, ref, songIds: [song.id]);
      case _SongAction.toggleFavorite:
        await ref.read(libraryRepositoryProvider).toggleFavorite(song.id);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              song.isFavorite
                  ? 'Removed “${song.displayTitle}” from favourites'
                  : 'Added “${song.displayTitle}” to favourites',
            ),
          ),
        );
      case _SongAction.info:
        await showSongInfoSheet(context, song);
    }
  }
}

/// Bottom sheet with everything the tags told us about a song.
Future<void> showSongInfoSheet(BuildContext context, Song song) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing24,
            0,
            ThemeConstants.spacing24,
            ThemeConstants.spacing24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AlbumArt(
                    artworkKey: song.artworkKey,
                    imageUrl: song.remoteArtworkUrl,
                    size: 72,
                    borderRadius: 16,
                  ),
                  const SizedBox(width: ThemeConstants.spacing16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.displayTitle,
                          style: theme.textTheme.titleLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: ThemeConstants.spacing4),
                        Text(
                          '${song.displayArtist} · ${song.displayAlbum}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacing24),
              Wrap(
                spacing: ThemeConstants.spacing8,
                runSpacing: ThemeConstants.spacing8,
                children: [
                  _InfoChip(
                    icon: Icons.schedule_rounded,
                    label: formatDuration(song.duration),
                  ),
                  if (song.year != null)
                    _InfoChip(
                      icon: Icons.calendar_today_rounded,
                      label: '${song.year}',
                    ),
                  if ((song.genre ?? '').trim().isNotEmpty)
                    _InfoChip(
                      icon: Icons.category_outlined,
                      label: song.genre!.trim(),
                    ),
                  if (song.trackNumber != null)
                    _InfoChip(
                      icon: Icons.tag_rounded,
                      label: song.discNumber != null
                          ? 'Disc ${song.discNumber}, track ${song.trackNumber}'
                          : 'Track ${song.trackNumber}',
                    ),
                  _InfoChip(
                    icon: Icons.data_usage_rounded,
                    label: formatFileSize(song.fileSize),
                  ),
                  _InfoChip(
                    icon: Icons.play_circle_outline_rounded,
                    label: song.playCount == 1
                        ? 'Played once'
                        : 'Played ${song.playCount} times',
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacing24),
              Divider(color: theme.colorScheme.outlineVariant),
              _InfoRow(
                icon: Icons.folder_outlined,
                label: 'File',
                value: song.filePath,
                selectable: true,
                onCopy: () {
                  Clipboard.setData(ClipboardData(text: song.filePath));
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text('File path copied')),
                  );
                },
              ),
              _InfoRow(
                icon: Icons.add_circle_outline_rounded,
                label: 'Added',
                value: formatRelativeDate(song.addedAt),
              ),
              if (song.lastPlayedAt != null)
                _InfoRow(
                  icon: Icons.history_rounded,
                  label: 'Last played',
                  value: formatRelativeDate(song.lastPlayedAt!),
                ),
              if (song.modifiedAt != null)
                _InfoRow(
                  icon: Icons.update_rounded,
                  label: 'File modified',
                  value: formatRelativeDate(song.modifiedAt!),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacing12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: ThemeConstants.spacing8),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.selectable = false,
    this.onCopy,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool selectable;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeConstants.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: ThemeConstants.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacing4),
                SelectableText(
                  value,
                  maxLines: selectable ? 3 : 1,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: onCopy,
            ),
        ],
      ),
    );
  }
}
