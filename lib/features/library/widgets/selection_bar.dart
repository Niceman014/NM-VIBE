import 'package:flutter/material.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';

/// Floating action bar shown while songs are multi-selected in the library.
class LibrarySelectionBar extends StatelessWidget {
  const LibrarySelectionBar({
    super.key,
    required this.count,
    required this.favouriteActive,
    required this.onFavourite,
    required this.onAddToPlaylist,
    required this.onQueue,
  });

  final int count;

  /// True when every selected song is already a favourite (action removes).
  final bool favouriteActive;
  final VoidCallback onFavourite;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing12,
        0,
        ThemeConstants.spacing12,
        ThemeConstants.spacing12,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: ThemeConstants.spacing8,
          vertical: ThemeConstants.spacing8,
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeConstants.spacing12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                  Text(
                    count == 1 ? 'song' : 'songs',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              indent: 6,
              endIndent: 6,
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _SelectionAction(
                    icon: favouriteActive
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: favouriteActive ? 'Unfavourite' : 'Favourite',
                    onTap: onFavourite,
                  ),
                  _SelectionAction(
                    icon: Icons.playlist_add_rounded,
                    label: 'Playlist',
                    onTap: onAddToPlaylist,
                  ),
                  _SelectionAction(
                    icon: Icons.queue_music_rounded,
                    label: 'Queue',
                    onTap: onQueue,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionAction extends StatelessWidget {
  const _SelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ThemeConstants.spacing8,
          vertical: ThemeConstants.spacing8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: scheme.onSurface),
            const SizedBox(height: ThemeConstants.spacing4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
