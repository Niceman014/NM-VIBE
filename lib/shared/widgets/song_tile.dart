import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/features/library/widgets/song_actions.dart';

/// Reusable song row used by the library, search, album, artist, playlist and
/// queue-like surfaces.
///
/// Keeps a deliberately small surface: [song], [onTap], [selected],
/// [trailing], [subtitle] — with optional extras for the playing indicator,
/// artwork size and selection mode. Every action lives in the overflow menu so
/// rows stay calm.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.onLongPress,
    this.subtitle,
    this.trailing,
    this.selected = false,
    this.selectionMode = false,
    this.isCurrent = false,
    this.isPlaying = false,
    this.showArtwork = true,
    this.showDuration = true,
    this.showActions = true,
    this.leading,
    this.artworkSize = 52,
  });

  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Defaults to the artist name. Pass an empty string to hide the line.
  final String? subtitle;
  final Widget? trailing;
  final bool selected;

  /// When true a checkbox replaces the artwork and taps toggle selection.
  final bool selectionMode;

  /// Highlights the row when this song is the one loaded in the player.
  final bool isCurrent;
  final bool isPlaying;
  final bool showArtwork;
  final bool showDuration;

  /// Hides the default overflow menu (used by the queue, which has its own).
  final bool showActions;
  final Widget? leading;
  final double artworkSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final subtitleText = subtitle ?? song.displayArtist;
    final highlight = selected || isCurrent;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacing8,
        vertical: ThemeConstants.spacing4,
      ),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeConstants.spacing8,
              vertical: 7,
            ),
            child: Row(
              children: [
                _buildLeading(context, scheme),
                const SizedBox(width: ThemeConstants.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        song.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: highlight
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: isCurrent ? scheme.primary : null,
                          letterSpacing: -0.1,
                        ),
                      ),
                      if (subtitleText.isNotEmpty) ...[
                        const SizedBox(height: ThemeConstants.spacing4),
                        Text(
                          subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: ThemeConstants.spacing8),
                _buildTrailing(context, scheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context, ColorScheme scheme) {
    if (selectionMode) {
      return SizedBox(
        width: artworkSize,
        height: artworkSize,
        child: Center(
          child: Checkbox(
            value: selected,
            onChanged: (_) => onTap?.call(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      );
    }
    if (leading != null) {
      return SizedBox(
        width: artworkSize,
        height: artworkSize,
        child: Center(child: leading),
      );
    }
    if (!showArtwork) {
      return SizedBox(width: artworkSize, height: artworkSize);
    }
    return AlbumArt(
      artworkKey: song.artworkKey,
      imageUrl: song.remoteArtworkUrl,
      size: artworkSize,
      borderRadius: 12,
      isPlaying: isCurrent && isPlaying,
    );
  }

  Widget _buildTrailing(BuildContext context, ColorScheme scheme) {
    if (trailing != null) return trailing!;
    if (selectionMode) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDuration)
          Text(
            formatDuration(song.duration),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        if (showActions) ...[
          const SizedBox(width: ThemeConstants.spacing4),
          SongActionsButton(song: song, variant: SongActionsVariant.tile),
        ],
      ],
    );
  }
}

/// Three softly animated equaliser bars marking the currently playing row.
class _PlayingBars extends StatefulWidget {
  const _PlayingBars({required this.color});

  final Color color;

  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ThemeConstants.reduceMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ThemeConstants.reduceMotion(context)) {
      return SizedBox(
        width: ThemeConstants.spacing16,
        height: ThemeConstants.spacing16,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var index = 0; index < ThemeConstants.spacing4; index++)
              _bar(8),
          ],
        ),
      );
    }
    return SizedBox(
      width: ThemeConstants.spacing12,
      height: ThemeConstants.spacing12,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          double heightFor(double phase) {
            final wave = (1 + math.sin(t * 2 * math.pi + phase)) / 2;
            return 4 + wave * 9;
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bar(heightFor(0)),
              _bar(heightFor(2.1)),
              _bar(heightFor(4.2)),
            ],
          );
        },
      ),
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 3,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
