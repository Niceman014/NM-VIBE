import 'package:flutter/material.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/data/models/library_groups.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';

/// A square album tile used by the albums tab and artist detail strips.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.album,
    this.isCurrent = false,
    this.onTap,
  });

  final AlbumGroup album;
  final bool isCurrent;
  final VoidCallback? onTap;

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
                      AlbumArt(
                        artworkKey: album.artworkKey,
                        size: side,
                        borderRadius: ThemeConstants.radiusMedium,
                      ),
                      if (isCurrent)
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.all(
                              ThemeConstants.spacing8,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: scheme.shadow.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              size: 16,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing4),
              Text(
                _subtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final year = album.year;
    final count = trackCountLabel(album.songs.length);
    return year == null
        ? '$count · ${album.artist}'
        : '$count · $year · ${album.artist}';
  }
}

/// A round artist tile for the artists tab.
class ArtistCard extends StatelessWidget {
  const ArtistCard({
    super.key,
    required this.artist,
    this.isCurrent = false,
    this.onTap,
  });

  final ArtistGroup artist;
  final bool isCurrent;
  final VoidCallback? onTap;

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
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final side = constraints.maxWidth;
                  return Stack(
                    children: [
                      AlbumArt(
                        artworkKey: artist.artworkKey,
                        size: side,
                        borderRadius: side / 2,
                        isPlaying: isCurrent,
                      ),
                      if (isCurrent)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: scheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.graphic_eq_rounded,
                              size: 14,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: ThemeConstants.spacing12),
              Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing4),
              Text(
                '${artist.albumCount == 1 ? '1 album' : '${artist.albumCount} albums'} · ${trackCountLabel(artist.songs.length)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact album tile for the horizontal strip on the artist page.
class AlbumStripCard extends StatelessWidget {
  const AlbumStripCard({super.key, required this.album, this.onTap});

  final AlbumGroup album;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const side = 132.0;

    return SizedBox(
      width: side + ThemeConstants.spacing8,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(ThemeConstants.spacing16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacing4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AlbumArt(
                  artworkKey: album.artworkKey,
                  size: side,
                  borderRadius: 14,
                ),
                const SizedBox(height: ThemeConstants.spacing8),
                Text(
                  album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  album.year == null
                      ? '${album.songs.length} songs'
                      : '${album.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
