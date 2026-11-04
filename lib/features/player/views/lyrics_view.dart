import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/features/player/services/lyrics_service.dart';
import 'package:nm_vibe/data/models/song_model.dart';

/// Opens the lyrics for the current track in a tall, draggable sheet.
Future<void> showLyricsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height;
      return SizedBox(height: height * 0.82, child: const LyricsView());
    },
  );
}

/// Caches parsed sidecar lyrics per song for as long as the sheet is open.
final _lyricsProvider = FutureProvider.autoDispose.family<Lyrics?, Song>(
  (ref, song) => ref.watch(lyricsServiceProvider).loadFor(song),
);

/// Synced / plain / empty lyrics for the current track.
///
/// Synced lyrics highlight the active line and keep it centred as playback
/// moves; tapping a line seeks to it. When no sidecar file exists the sheet
/// explains exactly how to add lyrics instead of showing a generic error.
class LyricsView extends ConsumerWidget {
  const LyricsView({super.key, this.song});

  /// Overrides the current player song (used for previews); defaults to live
  /// playback state.
  final Song? song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current =
        song ??
        ref.watch(playerControllerProvider.select((state) => state.current));

    if (current == null) {
      return const _LyricsMessage(
        icon: Icons.music_off_rounded,
        title: 'Nothing playing',
        message: 'Start a song to see its lyrics here.',
      );
    }

    final lyricsAsync = ref.watch(_lyricsProvider(current));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing24,
            0,
            ThemeConstants.spacing8,
            ThemeConstants.spacing8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lyrics', style: theme.textTheme.titleLarge),
                    const SizedBox(height: ThemeConstants.spacing4),
                    Text(
                      '${current.displayTitle} · ${current.displayArtist}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close lyrics',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: lyricsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => const _LyricsMessage(
              icon: Icons.lyrics_outlined,
              title: 'Could not read lyrics',
              message:
                  'The sidecar lyrics file for this song could not be '
                  'opened.',
            ),
            data: (lyrics) {
              if (lyrics == null) {
                return _LyricsMessage(
                  icon: Icons.lyrics_outlined,
                  title: 'No lyrics found',
                  message:
                      'Add a "${_baseNameOf(current)}.lrc" (synced) or '
                      '.txt file next to the audio file and reopen this sheet.',
                );
              }
              if (lyrics.synced && lyrics.lines.isNotEmpty) {
                return _SyncedLyrics(lines: lyrics.lines);
              }
              final plain = lyrics.plainText;
              if (plain != null && plain.trim().isNotEmpty) {
                return _PlainLyrics(text: plain);
              }
              return _LyricsMessage(
                icon: Icons.lyrics_outlined,
                title: 'No lyrics found',
                message:
                    'Add a "${_baseNameOf(current)}.lrc" (synced) or '
                    '.txt file next to the audio file and reopen this sheet.',
              );
            },
          ),
        ),
      ],
    );
  }

  static String _baseNameOf(Song song) {
    final path = song.filePath;
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}

/// Index of the lyric line that is active at [position], or -1 before the first
/// timestamp. Binary search keeps 4Hz position updates cheap.
int syncedLineIndex(List<LyricsLine> lines, Duration position) {
  if (lines.isEmpty) return -1;
  if (position < lines.first.time) return -1;
  var low = 0;
  var high = lines.length - 1;
  var result = -1;
  while (low <= high) {
    final mid = (low + high) >> 1;
    if (lines[mid].time <= position) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({required this.lines});

  final List<LyricsLine> lines;

  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  static const double _lineExtent = 64;

  final ScrollController _controller = ScrollController();
  int _lastIndex = -2;

  @override
  void didUpdateWidget(covariant _SyncedLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _lastIndex = -2;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToLine(
    int index,
    double viewportHeight, {
    required bool animate,
  }) {
    if (!_controller.hasClients) return;
    final target = (index * _lineExtent - (viewportHeight - _lineExtent) / 2)
        .clamp(0.0, _controller.position.maxScrollExtent)
        .toDouble();
    if (animate) {
      _controller.animateTo(
        target,
        duration: ThemeConstants.slow,
        curve: Curves.easeOutCubic,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final index = ref.watch(
      playerControllerProvider.select(
        (state) => syncedLineIndex(widget.lines, state.position),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (index != _lastIndex) {
          final animate = _lastIndex != -2;
          _lastIndex = index;
          if (index >= 0) {
            final targetIndex = index;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scrollToLine(
                  targetIndex,
                  constraints.maxHeight,
                  animate: animate && !ThemeConstants.reduceMotion(context),
                );
              }
            });
          }
        }

        return ListView.builder(
          controller: _controller,
          itemExtent: _lineExtent,
          padding: EdgeInsets.only(
            top: constraints.maxHeight * 0.32,
            bottom: constraints.maxHeight * 0.55,
          ),
          itemCount: widget.lines.length,
          itemBuilder: (context, lineIndex) {
            final line = widget.lines[lineIndex];
            final isCurrent = lineIndex == index;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  ref.read(playerControllerProvider.notifier).seek(line.time),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ThemeConstants.spacing24,
                      vertical: ThemeConstants.spacing8,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: ThemeConstants.motionDuration(
                        context,
                        ThemeConstants.medium,
                      ),
                      curve: Curves.easeOut,
                      style:
                          (isCurrent
                                  ? theme.textTheme.titleLarge
                                  : theme.textTheme.bodyLarge)
                              ?.copyWith(
                                color: isCurrent
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                height: 1.35,
                              ) ??
                          TextStyle(
                            fontSize: isCurrent ? 22 : 16,
                            height: 1.35,
                            color: isCurrent
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      child: Text(line.text, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing24,
        ThemeConstants.spacing24,
        ThemeConstants.spacing24,
        ThemeConstants.spacing32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SelectableText(
            text.trim(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.6,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricsMessage extends StatelessWidget {
  const _LyricsMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeConstants.spacing32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: scheme.onSurfaceVariant),
              const SizedBox(height: ThemeConstants.spacing12),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
