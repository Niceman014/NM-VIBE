import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/theme_constants.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/scanner/artwork_service.dart';

import '../../../shared/widgets/album_art.dart';

import 'package:nm_vibe/data/models/song_model.dart';

import '../controllers/palette_controller.dart';
import 'player_controls.dart';
import '../widgets/playback_error_banner.dart';

/// Full-screen player pushed above the app shell.
///
/// Everything on this page is derived from the playing song's artwork palette
/// blended with the Material 3 theme: the background wash, the progress colour,
/// active toggles and the play button. It is intentionally generous with space,
/// scrolls on short screens and moves to a two-column layout on desktop.
class NowPlayingPage extends ConsumerStatefulWidget {
  const NowPlayingPage({super.key});

  @override
  ConsumerState<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends ConsumerState<NowPlayingPage>
    with SingleTickerProviderStateMixin {
  static const double _dismissThreshold = 120;

  double _dragOffset = 0;
  double _snapFrom = 0;
  bool _hadSong = false;

  late final AnimationController _snapBackController = AnimationController(
    vsync: this,
    duration: ThemeConstants.fast,
  )..addListener(_onSnapBackTick);

  @override
  void dispose() {
    _snapBackController.dispose();
    super.dispose();
  }

  void _onSnapBackTick() {
    final eased = Curves.easeOutCubic.transform(_snapBackController.value);
    setState(() => _dragOffset = _snapFrom * (1 - eased));
  }

  void _onDragStart(DragStartDetails details) {
    _snapBackController.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (details.delta.dy <= 0 && _dragOffset <= 0) return;
    setState(() {
      _dragOffset = math.max(0, _dragOffset + details.delta.dy);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > _dismissThreshold || velocity > 650) {
      _snapBackController.stop();
      Navigator.of(context).maybePop();
      return;
    }
    if (_dragOffset > 0) {
      if (ThemeConstants.reduceMotion(context)) {
        setState(() => _dragOffset = 0);
        return;
      }
      _snapFrom = _dragOffset;
      _snapBackController.forward(from: 0);
    }
  }

  void _close() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final song = ref.watch(
      playerControllerProvider.select((state) => state.current),
    );
    final error = ref.watch(
      playerControllerProvider.select((state) => state.error),
    );
    final canSkipFailedTrack = ref.watch(
      playerControllerProvider.select((state) => state.canSkip),
    );
    final canRetryFailedTrack = ref.watch(
      playerControllerProvider.select((state) => state.canRetry),
    );

    ref.listen<bool>(
      playerControllerProvider.select((state) => state.hasSong),
      (previous, next) {
        if (_hadSong && !next && mounted) {
          _hadSong = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).maybePop();
          });
        }
      },
    );
    if (song != null) _hadSong = true;

    if (song == null) {
      return _NothingPlaying(onClose: _close);
    }

    final palette = ref.watch(artworkPaletteProvider(song.artworkKey)).value;
    final accent = harmonizedAccent(palette, scheme);

    return GestureDetector(
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _ImmersiveBackground(
              song: song,
              gradient: immersiveGradientColors(palette, scheme),
            ),
            SafeArea(
              bottom: false,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: Column(
                  children: [
                    const _PlayerTopBar(),
                    if (error != null)
                      PlaybackErrorBanner(
                        error: error,
                        onRetry: canRetryFailedTrack
                            ? () => ref
                                  .read(playerControllerProvider.notifier)
                                  .retry()
                            : null,
                        onSkip: canSkipFailedTrack
                            ? () => ref
                                  .read(playerControllerProvider.notifier)
                                  .skipFailedTrack()
                            : null,
                      ),
                    Expanded(
                      child: _PlayerContent(song: song, accent: accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blurred artwork wash behind the whole player, tinted by the palette gradient.
class _ImmersiveBackground extends ConsumerWidget {
  const _ImmersiveBackground({required this.song, required this.gradient});

  final Song song;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final file = ref.watch(artworkFileProvider(song.artworkKey)).value;
    final isDark = scheme.brightness == Brightness.dark;
    final cacheWidth = MediaQuery.sizeOf(context).width.round();

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomCenter,
                colors: gradient,
              ),
            ),
          ),
          if (file != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: isDark ? 0.30 : 0.16,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                    child: Transform.scale(
                      scale: 1.3,
                      child: Image.file(
                        file,
                        fit: BoxFit.cover,
                        cacheWidth: cacheWidth,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // Soft veil keeps foreground text readable over any artwork.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface.withValues(alpha: 0.04),
                  scheme.surface.withValues(alpha: isDark ? 0.72 : 0.62),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Top bar: drag handle, "now playing" label, queue position, close button.
class _PlayerTopBar extends ConsumerWidget {
  const _PlayerTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final sleepRemaining = ref.watch(
      playerControllerProvider.select((state) => state.sleepTimerRemaining),
    );
    final queuePosition = ref.watch(
      playerControllerProvider.select(
        (state) => (state.currentIndex, state.queue.length),
      ),
    );
    final (currentIndex, queueLength) = queuePosition;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? ThemeConstants.spacing32 : ThemeConstants.spacing12,
        ThemeConstants.spacing4,
        isWide ? ThemeConstants.spacing32 : ThemeConstants.spacing12,
        0,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ThemeConstants.spacing8,
            ),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.26),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Close player',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'NOW PLAYING',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (queueLength > 1)
                        Text(
                          '${currentIndex + 1} of $queueLength',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  width: ThemeConstants.spacing32,
                  child: sleepRemaining == null
                      ? const SizedBox.shrink()
                      : Tooltip(
                          message: 'Sleep timer running',
                          child: Icon(
                            Icons.bedtime_rounded,
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chooses the phone (single column, scrollable) or desktop (two column)
/// layout based on the width available for the player body.
class _PlayerContent extends StatelessWidget {
  const _PlayerContent({required this.song, required this.accent});

  final Song song;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return _DesktopPlayerLayout(
            song: song,
            accent: accent,
            constraints: constraints,
          );
        }
        return _PhonePlayerLayout(
          song: song,
          accent: accent,
          constraints: constraints,
        );
      },
    );
  }
}

class _PhonePlayerLayout extends StatelessWidget {
  const _PhonePlayerLayout({
    required this.song,
    required this.accent,
    required this.constraints,
  });

  final Song song;
  final Color accent;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final horizontal = constraints.maxWidth < 380 ? 20.0 : 28.0;
    final artSize = math
        .min(
          constraints.maxWidth - horizontal * 2,
          constraints.maxHeight * 0.38,
        )
        .clamp(140.0, 400.0)
        .toDouble();
    final compact = constraints.maxHeight < 640;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontal,
        ThemeConstants.spacing4,
        horizontal,
        ThemeConstants.spacing24 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        children: [
          _ArtworkStage(song: song, accent: accent, size: artSize),
          SizedBox(
            height: compact
                ? ThemeConstants.spacing16
                : ThemeConstants.spacing24,
          ),
          _TrackInfo(song: song, accent: accent),
          SizedBox(
            height: compact
                ? ThemeConstants.spacing8
                : ThemeConstants.spacing16,
          ),
          PlayerSeekBar(accent: accent),
          SizedBox(
            height: compact ? ThemeConstants.spacing4 : ThemeConstants.spacing8,
          ),
          PlayerTransportBar(accent: accent, compact: compact),
          SizedBox(
            height: compact
                ? ThemeConstants.spacing16
                : ThemeConstants.spacing24,
          ),
          PlayerActionRow(accent: accent),
        ],
      ),
    );
  }
}

class _DesktopPlayerLayout extends StatelessWidget {
  const _DesktopPlayerLayout({
    required this.song,
    required this.accent,
    required this.constraints,
  });

  final Song song;
  final Color accent;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final artSize = math
        .min(
          constraints.maxWidth * 0.30,
          math.min(constraints.maxHeight * 0.72, 460.0),
        )
        .clamp(220.0, 460.0)
        .toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing32,
        ThemeConstants.spacing8,
        ThemeConstants.spacing32,
        ThemeConstants.spacing16,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Center(
              child: _ArtworkStage(song: song, accent: accent, size: artSize),
            ),
          ),
          const SizedBox(width: 64),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TrackInfo(song: song, accent: accent),
                      const SizedBox(height: ThemeConstants.spacing24),
                      PlayerSeekBar(accent: accent),
                      const SizedBox(height: ThemeConstants.spacing12),
                      PlayerTransportBar(accent: accent),
                      const SizedBox(height: ThemeConstants.spacing32),
                      PlayerActionRow(accent: accent),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large Hero artwork with an ambient glow in the album's colour.
class _ArtworkStage extends ConsumerWidget {
  const _ArtworkStage({
    required this.song,
    required this.accent,
    required this.size,
  });

  final Song song;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playing = ref.watch(
      playerControllerProvider.select((state) => state.playing),
    );
    final radius = size < 240
        ? ThemeConstants.radiusLarge
        : ThemeConstants.radiusXLarge;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient glow painted behind the artwork.
          IgnorePointer(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.42),
                    blurRadius: size * 0.24,
                    spreadRadius: size * 0.01,
                    offset: Offset(0, size * 0.07),
                  ),
                ],
              ),
            ),
          ),
          AlbumArt(
            artworkKey: song.artworkKey,
            imageUrl: song.remoteArtworkUrl,
            size: size,
            borderRadius: radius,
            isPlaying: playing,
            heroTag: albumArtHeroTag(song.id),
            semanticLabel: 'Artwork for ${song.displayTitle}',
          ),
        ],
      ),
    );
  }
}

/// Title, artist, album line and the favourite toggle.
class _TrackInfo extends StatelessWidget {
  const _TrackInfo({required this.song, required this.accent});

  final Song song;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final titleStyle =
        (isWide
                ? theme.textTheme.headlineMedium
                : theme.textTheme.headlineSmall)
            ?.copyWith(fontWeight: FontWeight.w800, height: 1.1);
    final albumLine = song.year == null
        ? song.displayAlbum
        : '${song.displayAlbum} · ${song.year}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                song.displayArtist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing4),
              Text(
                albumLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: ThemeConstants.spacing12),
        _FavoriteButton(song: song, accent: accent),
      ],
    );
  }
}

/// Optimistic favourite toggle backed by the library repository.
class _FavoriteButton extends ConsumerStatefulWidget {
  const _FavoriteButton({required this.song, required this.accent});

  final Song song;
  final Color accent;

  @override
  ConsumerState<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<_FavoriteButton> {
  String? _pendingSongId;
  bool? _pendingValue;
  bool _busy = false;

  bool _persistedFavorite(AsyncValue<List<Song>> value) {
    final songs = value.value;
    if (songs != null) {
      for (final song in songs) {
        if (song.id == widget.song.id) return song.isFavorite;
      }
    }
    return widget.song.isFavorite;
  }

  Future<void> _toggle(bool selected) async {
    if (_busy) return;
    final target = !selected;
    setState(() {
      _busy = true;
      _pendingSongId = widget.song.id;
      _pendingValue = target;
    });
    try {
      await ref.read(libraryRepositoryProvider).toggleFavorite(widget.song.id);
      ref.invalidate(songsProvider);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pendingSongId = null;
        _pendingValue = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update favourite: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final persisted = _persistedFavorite(ref.watch(songsProvider));
    final selected = _pendingSongId == widget.song.id
        ? (_pendingValue ?? persisted)
        : persisted;
    final heartColor = selected ? widget.accent : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      label: selected ? 'Remove from favourites' : 'Add to favourites',
      child: AnimatedScale(
        scale: _busy ? 0.92 : 1,
        duration: ThemeConstants.motionDuration(context, ThemeConstants.fast),
        child: IconButton(
          tooltip: selected ? 'Remove from favourites' : 'Add to favourites',
          onPressed: _busy ? null : () => _toggle(selected),
          iconSize: 26,
          style: IconButton.styleFrom(
            minimumSize: const Size(48, 48),
            backgroundColor: selected
                ? widget.accent.withValues(alpha: 0.18)
                : scheme.onSurface.withValues(alpha: 0.06),
            foregroundColor: heartColor,
          ),
          icon: AnimatedSwitcher(
            duration: ThemeConstants.motionDuration(
              context,
              ThemeConstants.fast,
            ),
            transitionBuilder: (child, animation) {
              return ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: Icon(
              selected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey<bool>(selected),
              color: heartColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _NothingPlaying extends StatelessWidget {
  const _NothingPlaying({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: 0.55),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(ThemeConstants.spacing8),
                  child: IconButton(
                    tooltip: 'Close player',
                    onPressed: onClose,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 30,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(ThemeConstants.spacing32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              ThemeConstants.radiusXLarge,
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.primaryContainer,
                                scheme.tertiaryContainer,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.music_off_rounded,
                            size: 44,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: ThemeConstants.spacing24),
                        Text(
                          'Nothing playing',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: ThemeConstants.spacing8),
                        Text(
                          'Pick a song from your library and it will show up '
                          'here, ready for the vibe.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preloads the queue, opens Now Playing, and starts audio after its route
/// transition completes. This keeps the first Windows audio start away from
/// the shared-artwork route rebuild.
Future<void> playSongsAndOpen(
  BuildContext context,
  WidgetRef ref,
  List<Song> songs, {
  int initialIndex = 0,
}) async {
  final controller = ref.read(playerControllerProvider.notifier);
  await controller.playSongs(
    songs,
    initialIndex: initialIndex,
    autoPlay: false,
  );
  if (!context.mounted) return;

  openNowPlaying(context);
  await Future<void>.delayed(const Duration(milliseconds: 460));
  if (!context.mounted || ref.read(playerControllerProvider).error != null) {
    return;
  }
  unawaited(controller.togglePlayPause());
}

/// Opens the full-screen player above the shell.
void openNowPlaying(BuildContext context) {
  Navigator.of(
    context,
    rootNavigator: true,
  ).push(_nowPlayingRoute(reduceMotion: ThemeConstants.reduceMotion(context)));
}

Route<void> _nowPlayingRoute({required bool reduceMotion}) {
  return PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: reduceMotion ? Duration.zero : ThemeConstants.medium,
    reverseTransitionDuration: reduceMotion
        ? Duration.zero
        : ThemeConstants.medium,
    pageBuilder: (context, animation, secondaryAnimation) =>
        const NowPlayingPage(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.08),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Convenience for pages that only know they have a song.
void playSongAndOpen(BuildContext context, WidgetRef ref, Song song) {
  ref.read(playerControllerProvider.notifier).playSong(song);
  openNowPlaying(context);
}
