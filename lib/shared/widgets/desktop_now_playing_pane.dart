import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/navigation/open_now_playing.dart';
import 'album_art.dart';

/// Persistent companion pane used by the Windows and wide desktop layouts.
class DesktopNowPlayingPane extends ConsumerStatefulWidget {
  const DesktopNowPlayingPane({super.key});

  @override
  ConsumerState<DesktopNowPlayingPane> createState() =>
      _DesktopNowPlayingPaneState();
}

class _DesktopNowPlayingPaneState extends ConsumerState<DesktopNowPlayingPane> {
  double? _scrubProgress;

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(
      playerControllerProvider.select(
        (state) => (
          song: state.current,
          playing: state.playing,
          loading: state.loading,
          position: state.position,
          duration: state.duration,
          progress: state.progress,
          queueLength: state.queue.length,
        ),
      ),
    );
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final song = player.song;

    return ColoredBox(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ThemeConstants.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.graphic_eq_rounded, color: scheme.primary),
                  const SizedBox(width: ThemeConstants.spacing8),
                  Expanded(
                    child: Text(
                      'NOW PLAYING',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  Text(
                    '${player.queueLength} ${player.queueLength == 1 ? 'track' : 'tracks'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConstants.spacing24),
              if (song == null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.queue_music_rounded,
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: ThemeConstants.spacing12),
                        Text(
                          'Choose a song to start listening',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final artSize = math.min(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Center(
                        child: AlbumArt(
                          artworkKey: song.artworkKey,
                          imageUrl: song.remoteArtworkUrl,
                          size: artSize,
                          borderRadius: ThemeConstants.radiusLarge,
                          isPlaying: player.playing,
                          heroTag: albumArtHeroTag(song.id),
                          semanticLabel: 'Artwork for ${song.displayTitle}',
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacing24),
                Text(
                  song.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: ThemeConstants.spacing4),
                Text(
                  song.displayArtist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacing16),
                Slider(
                  value: _scrubProgress ?? player.progress,
                  semanticFormatterCallback: (value) =>
                      formatDuration(player.duration * value),
                  onChangeStart: player.duration > Duration.zero
                      ? (value) => setState(() => _scrubProgress = value)
                      : null,
                  onChanged: player.duration > Duration.zero
                      ? (value) => setState(() => _scrubProgress = value)
                      : null,
                  onChangeEnd: player.duration > Duration.zero
                      ? (value) {
                          setState(() => _scrubProgress = null);
                          unawaited(
                            ref
                                .read(playerControllerProvider.notifier)
                                .seek(player.duration * value),
                          );
                        }
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: ThemeConstants.spacing8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatDuration(player.position),
                        style: theme.textTheme.labelSmall,
                      ),
                      Text(
                        formatDuration(player.duration),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: ThemeConstants.spacing8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous track',
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .previous(),
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: ThemeConstants.spacing16),
                    Tooltip(
                      message: player.playing ? 'Pause' : 'Play',
                      child: FilledButton(
                        onPressed: player.loading
                            ? null
                            : () => ref
                                  .read(playerControllerProvider.notifier)
                                  .togglePlayPause(),
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(
                            ThemeConstants.spacing12,
                          ),
                        ),
                        child: Icon(
                          player.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(width: ThemeConstants.spacing16),
                    IconButton(
                      tooltip: 'Next track',
                      onPressed: () =>
                          ref.read(playerControllerProvider.notifier).next(),
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacing8),
                TextButton.icon(
                  onPressed: () => openNowPlaying(context),
                  icon: const Icon(Icons.open_in_full_rounded),
                  label: const Text('Open full player'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
