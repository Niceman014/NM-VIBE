import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/album_art.dart';
import 'package:nm_vibe/data/models/song_model.dart';

/// Opens the queue as a draggable bottom sheet.
Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const QueueSheet(),
  );
}

/// Reorderable queue: tap a row to jump there, swipe or use the remove button to
/// drop a track, drag the handle to rearrange what plays next.
class QueueSheet extends ConsumerWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(
      playerControllerProvider.select(
        (state) => (state.queue, state.currentIndex, state.playing),
      ),
    );
    final (queue, currentIndex, playing) = state;
    final height = math.min(MediaQuery.sizeOf(context).height * 0.82, 780.0);

    if (queue.isEmpty) {
      return SizedBox(
        height: math.min(320, height),
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
              Text('Your queue is empty', style: theme.textTheme.titleMedium),
              const SizedBox(height: ThemeConstants.spacing4),
              Text(
                'Play a song from your library to fill it up.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final total = queue.fold<Duration>(
      Duration.zero,
      (sum, song) => sum + song.duration,
    );
    final upcoming = math.max(0, queue.length - currentIndex - 1);

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeConstants.spacing24,
              0,
              ThemeConstants.spacing12,
              ThemeConstants.spacing8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Queue', style: theme.textTheme.titleLarge),
                      const SizedBox(height: ThemeConstants.spacing4),
                      Text(
                        '${trackCountLabel(queue.length)} · '
                        '${formatTotalDuration(total)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _confirmClear(context, ref, queue.length),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeConstants.spacing24,
              0,
              ThemeConstants.spacing24,
              ThemeConstants.spacing8,
            ),
            child: Row(
              children: [
                Text(
                  'PLAYING NEXT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  upcoming == 0
                      ? 'End of queue'
                      : '$upcoming track${upcoming == 1 ? '' : 's'} left',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(
                vertical: ThemeConstants.spacing8,
              ),
              itemCount: queue.length,
              onReorder: (oldIndex, newIndex) => ref
                  .read(playerControllerProvider.notifier)
                  .reorderQueue(oldIndex, newIndex),
              itemBuilder: (context, index) {
                final song = queue[index];
                final isCurrent = index == currentIndex;
                return Dismissible(
                  key: ValueKey<String>('queue-$index-${song.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: ThemeConstants.spacing8,
                      vertical: ThemeConstants.spacing4,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: ThemeConstants.spacing24,
                    ),
                    alignment: Alignment.centerRight,
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(
                        ThemeConstants.radiusMedium,
                      ),
                    ),
                    child: Icon(
                      Icons.remove_circle_outline_rounded,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  onDismissed: (_) => ref
                      .read(playerControllerProvider.notifier)
                      .removeFromQueue(index),
                  child: _QueueTile(
                    song: song,
                    index: index,
                    isCurrent: isCurrent,
                    playing: playing,
                    accent: scheme.primary,
                    onTap: () => _jumpTo(context, ref, queue, index, isCurrent),
                    onRemove: () => ref
                        .read(playerControllerProvider.notifier)
                        .removeFromQueue(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _jumpTo(
    BuildContext context,
    WidgetRef ref,
    List<Song> queue,
    int index,
    bool isCurrent,
  ) {
    final controller = ref.read(playerControllerProvider.notifier);
    if (isCurrent) {
      final player = ref.read(playerControllerProvider);
      if (!player.playing) {
        controller.togglePlayPause();
      }
      return;
    }
    controller.playSongs(List<Song>.of(queue), initialIndex: index);
  }

  Future<void> _confirmClear(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear the queue?'),
        content: Text(
          'This stops playback and removes ${trackCountLabel(count)} '
          'from the queue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear queue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(playerControllerProvider.notifier).clearQueue();
    if (context.mounted) Navigator.of(context).maybePop();
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.playing,
    required this.accent,
    required this.onTap,
    required this.onRemove,
  });

  final Song song;
  final int index;
  final bool isCurrent;
  final bool playing;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
      color: isCurrent ? accent : scheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacing8,
        vertical: ThemeConstants.spacing4,
      ),
      child: Material(
        color: isCurrent ? accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeConstants.spacing8,
              ThemeConstants.spacing8,
              ThemeConstants.spacing4,
              ThemeConstants.spacing8,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: ThemeConstants.spacing24,
                  child: Center(
                    child: isCurrent
                        ? _PlayingBars(accent: accent, playing: playing)
                        : Text(
                            '${index + 1}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                ui.FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                  ),
                ),
                AlbumArt(
                  artworkKey: song.artworkKey,
                  imageUrl: song.remoteArtworkUrl,
                  size: 44,
                  borderRadius: 10,
                  isPlaying: isCurrent && playing,
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
                        style: titleStyle,
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
                const SizedBox(width: ThemeConstants.spacing8),
                Text(
                  formatDuration(song.duration),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove from queue',
                  onPressed: onRemove,
                  iconSize: 18,
                  padding: const EdgeInsets.all(ThemeConstants.spacing8),
                  constraints: const BoxConstraints(
                    minWidth: ThemeConstants.minimumTapTarget,
                    minHeight: ThemeConstants.minimumTapTarget,
                  ),
                  icon: Icon(
                    Icons.close_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ThemeConstants.spacing4,
                      vertical: ThemeConstants.spacing8,
                    ),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 22,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
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

/// Three small animated bars that mark the currently playing queue row.
class _PlayingBars extends StatefulWidget {
  const _PlayingBars({required this.accent, required this.playing});

  final Color accent;
  final bool playing;

  @override
  State<_PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<_PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ThemeConstants.reduceMotion(context)) {
      _controller.stop();
    } else if (widget.playing && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing &&
        !ThemeConstants.reduceMotion(context) &&
        !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.playing && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = ThemeConstants.reduceMotion(context);
    return SizedBox(
      width: ThemeConstants.spacing16,
      height: ThemeConstants.spacing16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 3,
                  height: reduceMotion || !widget.playing
                      ? 6
                      : 5 +
                            9 *
                                ((math.sin(
                                          _controller.value * 2 * math.pi +
                                              i * 2.2,
                                        ) +
                                        1) /
                                    2),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
