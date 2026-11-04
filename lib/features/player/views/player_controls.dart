import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import '../../../core/utils/formatters.dart';
import 'package:nm_vibe/core/platform/platform_info.dart';
import '../controllers/palette_controller.dart';
import 'equalizer_sheet.dart';
import 'lyrics_view.dart';
import 'queue_sheet.dart';

/// Seek bar with a distinct buffered range and elapsed / remaining labels.
class PlayerSeekBar extends ConsumerStatefulWidget {
  const PlayerSeekBar({super.key, required this.accent});

  final Color accent;

  @override
  ConsumerState<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends ConsumerState<PlayerSeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(
      playerControllerProvider.select(
        (state) => (state.position, state.duration, state.buffered),
      ),
    );
    final (position, duration, buffered) = state;
    final durationMs = duration.inMilliseconds;

    final fraction = durationMs <= 0
        ? 0.0
        : (position.inMilliseconds / durationMs).clamp(0.0, 1.0).toDouble();
    final bufferedFraction = durationMs <= 0
        ? 0.0
        : (buffered.inMilliseconds / durationMs).clamp(0.0, 1.0).toDouble();
    final displayedFraction = _dragValue ?? fraction;
    final displayedPosition = durationMs <= 0
        ? Duration.zero
        : duration * displayedFraction;
    final enabled = durationMs > 0;
    final inactiveColor = scheme.onSurface.withValues(alpha: 0.16);
    final bufferedColor = scheme.onSurface.withValues(alpha: 0.32);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            activeTrackColor: widget.accent,
            inactiveTrackColor: inactiveColor,
            thumbColor: widget.accent,
            overlayColor: widget.accent.withValues(alpha: 0.14),
            trackShape: _BufferedTrackShape(
              activeColor: widget.accent,
              inactiveColor: inactiveColor,
              bufferedColor: bufferedColor,
              bufferedFraction: bufferedFraction,
            ),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 7,
              elevation: 2,
              pressedElevation: 5,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: displayedFraction,
            semanticFormatterCallback: (value) =>
                formatDuration(duration * value),
            onChangeStart: enabled
                ? (value) => setState(() => _dragValue = value)
                : null,
            onChanged: enabled
                ? (value) => setState(() => _dragValue = value)
                : null,
            onChangeEnd: enabled
                ? (value) {
                    setState(() => _dragValue = null);
                    ref
                        .read(playerControllerProvider.notifier)
                        .seek(duration * value);
                  }
                : null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ThemeConstants.spacing8,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatDuration(displayedPosition),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
              Text(
                durationMs <= 0 ? '0:00' : formatDuration(duration),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Track shape that paints inactive, buffered and played ranges separately.
class _BufferedTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _BufferedTrackShape({
    required this.activeColor,
    required this.inactiveColor,
    required this.bufferedColor,
    required this.bufferedFraction,
  });

  final Color activeColor;
  final Color inactiveColor;
  final Color bufferedColor;
  final double bufferedFraction;

  @override
  bool get isRounded => true;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;
    final radius = Radius.circular(rect.height / 2);
    final canvas = context.canvas;
    final paint = Paint()..isAntiAlias = true;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      paint..color = inactiveColor,
    );

    final bufferedRight =
        (rect.left + rect.width * bufferedFraction.clamp(0.0, 1.0).toDouble())
            .clamp(rect.left, rect.right)
            .toDouble();
    if (bufferedRight > rect.left) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(rect.left, rect.top, bufferedRight, rect.bottom),
          radius,
        ),
        paint..color = bufferedColor,
      );
    }

    final thumbX = thumbCenter.dx.clamp(rect.left, rect.right).toDouble();
    final activeRect = textDirection == TextDirection.ltr
        ? Rect.fromLTRB(rect.left, rect.top, thumbX, rect.bottom)
        : Rect.fromLTRB(thumbX, rect.top, rect.right, rect.bottom);
    if (activeRect.width > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        paint..color = activeColor,
      );
    }
  }
}

/// Shuffle / previous / play-pause / next / repeat row.
class PlayerTransportBar extends ConsumerWidget {
  const PlayerTransportBar({
    super.key,
    required this.accent,
    this.compact = false,
  });

  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      playerControllerProvider.select(
        (state) => (
          state.playing,
          state.loading,
          state.shuffleEnabled,
          state.repeatMode,
        ),
      ),
    );
    final (playing, loading, shuffle, repeatMode) = state;
    final controller = ref.read(playerControllerProvider.notifier);
    final repeatActive = repeatMode != AudioServiceRepeatMode.none;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _ModeButton(
          icon: Icons.shuffle_rounded,
          tooltip: shuffle ? 'Shuffle on' : 'Shuffle off',
          active: shuffle,
          accent: accent,
          onPressed: controller.toggleShuffle,
        ),
        _SkipButton(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous track',
          onPressed: controller.previous,
        ),
        _PlayPauseButton(
          playing: playing,
          loading: loading,
          accent: accent,
          size: compact ? 62 : 70,
          onPressed: controller.togglePlayPause,
        ),
        _SkipButton(
          icon: Icons.skip_next_rounded,
          tooltip: 'Next track',
          onPressed: controller.next,
        ),
        _ModeButton(
          icon: repeatMode == AudioServiceRepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          tooltip: repeatMode == AudioServiceRepeatMode.one
              ? 'Repeat one'
              : repeatMode == AudioServiceRepeatMode.all
              ? 'Repeat queue'
              : 'Repeat off',
          active: repeatActive,
          accent: accent,
          onPressed: controller.cycleRepeatMode,
        ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 40,
      padding: const EdgeInsets.all(ThemeConstants.spacing8),
      color: Theme.of(context).colorScheme.onSurface,
      icon: Icon(icon),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.accent,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(ThemeConstants.spacing8),
      icon: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Icon(
            icon,
            size: 24,
            color: active ? accent : scheme.onSurfaceVariant,
          ),
          if (active)
            Positioned(
              bottom: -7,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.playing,
    required this.loading,
    required this.accent,
    required this.size,
    required this.onPressed,
  });

  final bool playing;
  final bool loading;
  final Color accent;
  final double size;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = foregroundOn(accent);
    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.38),
              blurRadius: size * 0.36,
              offset: Offset(0, size * 0.12),
            ),
          ],
        ),
        child: Material(
          color: accent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: loading ? null : onPressed,
            child: Center(
              child: loading
                  ? SizedBox(
                      width: size * 0.36,
                      height: size * 0.36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: foreground,
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
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Padding(
                        key: ValueKey<bool>(playing),
                        padding: EdgeInsets.only(
                          left: playing ? 0 : size * 0.04,
                        ),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: size * 0.52,
                          color: foreground,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary actions under the transport row: lyrics, queue, speed, sleep, EQ.
class PlayerActionRow extends ConsumerStatefulWidget {
  const PlayerActionRow({super.key, required this.accent});

  final Color accent;

  @override
  ConsumerState<PlayerActionRow> createState() => _PlayerActionRowState();
}

class _PlayerActionRowState extends ConsumerState<PlayerActionRow> {
  bool _lyricsOpen = false;

  Future<void> _openLyrics() async {
    setState(() => _lyricsOpen = true);
    try {
      await showLyricsSheet(context);
    } finally {
      if (mounted) setState(() => _lyricsOpen = false);
    }
  }

  Future<void> _openSpeed() => _showSpeedSheet(context, ref);

  Future<void> _openSleep() => _showSleepTimerSheet(context, ref);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(
      playerControllerProvider.select(
        (state) => (state.speed, state.sleepTimerRemaining),
      ),
    );
    final (speed, sleepRemaining) = state;
    final showLyrics = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.showLyricsInPlayer,
      ),
    );

    final actions = <Widget>[
      if (showLyrics)
        _PlayerAction(
          icon: Icons.lyrics_rounded,
          label: 'Lyrics',
          active: _lyricsOpen,
          accent: widget.accent,
          onPressed: _openLyrics,
          tooltip: 'Show lyrics',
        ),
      _PlayerAction(
        icon: Icons.queue_music_rounded,
        label: 'Queue',
        active: false,
        accent: widget.accent,
        onPressed: () => showQueueSheet(context),
        tooltip: 'Show queue',
      ),
      _PlayerAction(
        icon: Icons.speed_rounded,
        label: speed == 1.0 ? 'Speed' : formatPlaybackSpeed(speed),
        active: speed != 1.0,
        accent: widget.accent,
        onPressed: _openSpeed,
        tooltip: 'Playback speed',
      ),
      _PlayerAction(
        icon: sleepRemaining == null
            ? Icons.bedtime_outlined
            : Icons.bedtime_rounded,
        label: sleepRemaining == null
            ? 'Sleep'
            : formatDuration(sleepRemaining),
        active: sleepRemaining != null,
        accent: widget.accent,
        onPressed: _openSleep,
        tooltip: sleepRemaining == null
            ? 'Sleep timer'
            : 'Sleep timer: ${formatDuration(sleepRemaining)} left',
      ),
      if (PlatformInfo.supportsEqualizer)
        _PlayerAction(
          icon: Icons.graphic_eq_rounded,
          label: 'EQ',
          active: false,
          accent: widget.accent,
          onPressed: () => showEqualizerSheet(context),
          tooltip: 'Equalizer',
        ),
    ];

    return Row(
      children: [
        for (final action in actions) Expanded(child: Center(child: action)),
      ],
    );
  }
}

class _PlayerAction extends StatelessWidget {
  const _PlayerAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.accent,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 34,
        containedInkWell: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ThemeConstants.spacing4,
            vertical: ThemeConstants.spacing4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: ThemeConstants.motionDuration(
                  context,
                  ThemeConstants.fast,
                ),
                curve: Curves.easeOut,
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? accent.withValues(alpha: 0.20)
                      : scheme.onSurface.withValues(alpha: 0.06),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: active ? accent : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: active ? accent : scheme.onSurfaceVariant,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- speed sheet
Future<void> _showSpeedSheet(BuildContext context, WidgetRef ref) async {
  final current = ref.read(playerControllerProvider).speed;
  final selected = await showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: ThemeConstants.spacing16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing24,
                  0,
                  ThemeConstants.spacing24,
                  ThemeConstants.spacing8,
                ),
                child: Text(
                  'Playback speed',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              for (final speed in const <double>[
                0.5,
                0.75,
                1,
                1.25,
                1.5,
                1.75,
                2,
              ])
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ThemeConstants.spacing24,
                    vertical: 0,
                  ),
                  title: Text(
                    speed == 1 ? 'Normal (1x)' : formatPlaybackSpeed(speed),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: current == speed
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: current == speed
                      ? Icon(
                          Icons.check_rounded,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  selected: current == speed,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      ThemeConstants.radiusMedium,
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(speed),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (selected == null) return;
  await ref.read(playerControllerProvider.notifier).setSpeed(selected);
}

// ---------------------------------------------------------- sleep timer sheet
Future<void> _showSleepTimerSheet(BuildContext context, WidgetRef ref) async {
  final remaining = ref.read(playerControllerProvider).sleepTimerRemaining;
  final minutes = await showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      const options = <int>[5, 10, 15, 20, 30, 45, 60, 90];
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: ThemeConstants.spacing16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing24,
                  0,
                  ThemeConstants.spacing24,
                  ThemeConstants.spacing8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sleep timer', style: theme.textTheme.titleLarge),
                    if (remaining != null) ...[
                      const SizedBox(height: ThemeConstants.spacing4),
                      Text(
                        'Pausing in ${formatDuration(remaining)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (remaining != null)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ThemeConstants.spacing24,
                    vertical: 0,
                  ),
                  leading: Icon(
                    Icons.timer_off_rounded,
                    color: theme.colorScheme.error,
                  ),
                  title: const Text('Turn off timer'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      ThemeConstants.radiusMedium,
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(0),
                ),
              for (final value in options)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: ThemeConstants.spacing24,
                    vertical: 0,
                  ),
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text('$value minutes'),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      ThemeConstants.radiusMedium,
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(value),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (minutes == null) return;
  ref
      .read(playerControllerProvider.notifier)
      .setSleepTimer(minutes <= 0 ? null : Duration(minutes: minutes));
}
