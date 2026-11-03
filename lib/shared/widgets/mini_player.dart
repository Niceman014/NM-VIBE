import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/features/player/controllers/palette_controller.dart';
import 'package:nm_vibe/shared/navigation/open_now_playing.dart';
import 'album_art.dart';

/// Compact now-playing bar pinned above the navigation bar.
///
/// Hides itself completely while nothing is playing, so the library always gets
/// the full height. Tap or swipe up to open the full player.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final song = player.current;

    if (!player.hasSong || song == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = ref.watch(artworkPaletteProvider(song.artworkKey)).value;
    final accent = harmonizedAccent(palette, scheme);
    final surface = playerPanelColor(palette, scheme);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: ThemeConstants.motionDuration(context, ThemeConstants.medium),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ThemeConstants.spacing12,
          ThemeConstants.spacing4,
          ThemeConstants.spacing12,
          ThemeConstants.spacing8,
        ),
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -220) {
              openNowPlaying(context);
            }
          },
          child: Material(
            color: surface,
            borderRadius: BorderRadius.circular(ThemeConstants.radiusLarge),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => openNowPlaying(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MiniProgressBar(
                    progress: player.progress,
                    buffered: player.duration.inMilliseconds > 0
                        ? (player.buffered.inMilliseconds /
                                  player.duration.inMilliseconds)
                              .clamp(0.0, 1.0)
                              .toDouble()
                        : 0.0,
                    activeColor: accent,
                    trackColor: scheme.onSurface.withValues(alpha: 0.12),
                    bufferedColor: scheme.onSurface.withValues(alpha: 0.26),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      ThemeConstants.spacing8,
                      ThemeConstants.spacing8,
                      ThemeConstants.spacing4,
                      ThemeConstants.spacing8,
                    ),
                    child: Row(
                      children: [
                        AlbumArt(
                          artworkKey: song.artworkKey,
                          imageUrl: song.remoteArtworkUrl,
                          size: 46,
                          borderRadius: 12,
                          isPlaying: player.playing,
                          heroTag: albumArtHeroTag(song.id),
                          semanticLabel: 'Artwork for ${song.displayTitle}',
                        ),
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
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: ThemeConstants.spacing4),
                              Text(
                                song.displayArtist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: ThemeConstants.spacing4),
                        _MiniButton(
                          tooltip: player.playing ? 'Pause' : 'Play',
                          onPressed: () => ref
                              .read(playerControllerProvider.notifier)
                              .togglePlayPause(),
                          child: player.loading
                              ? SizedBox(
                                  width: ThemeConstants.spacing24,
                                  height: ThemeConstants.spacing24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: ThemeConstants.spacing4,
                                    color: accent,
                                  ),
                                )
                              : AnimatedSwitcher(
                                  duration: ThemeConstants.motionDuration(
                                    context,
                                    ThemeConstants.fast,
                                  ),
                                  transitionBuilder: (child, animation) {
                                    return ScaleTransition(
                                      scale: animation,
                                      child: child,
                                    );
                                  },
                                  child: Icon(
                                    player.playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    key: ValueKey<bool>(player.playing),
                                    size: 28,
                                    color: scheme.onSurface,
                                  ),
                                ),
                        ),
                        _MiniButton(
                          tooltip: 'Next track',
                          onPressed: () => ref
                              .read(playerControllerProvider.notifier)
                              .next(),
                          child: Icon(
                            Icons.skip_next_rounded,
                            size: 26,
                            color: scheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin two-layer progress line: buffered range behind the played range.
class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({
    required this.progress,
    required this.buffered,
    required this.activeColor,
    required this.trackColor,
    required this.bufferedColor,
  });

  final double progress;
  final double buffered;
  final Color activeColor;
  final Color trackColor;
  final Color bufferedColor;

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();
    final safeBuffered = buffered.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: ThemeConstants.spacing4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: trackColor),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: safeBuffered,
            child: ColoredBox(color: bufferedColor),
          ),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: safeProgress,
            child: ColoredBox(color: activeColor),
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 26,
      constraints: const BoxConstraints(
        minWidth: ThemeConstants.minimumTapTarget,
        minHeight: ThemeConstants.minimumTapTarget,
      ),
      padding: const EdgeInsets.all(ThemeConstants.spacing8),
      icon: child,
    );
  }
}
