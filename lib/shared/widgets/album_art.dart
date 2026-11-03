import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/core/scanner/artwork_service.dart';

/// Artwork thumbnail used everywhere in NM VIBE.
///
/// The widget is intentionally self-contained: give it an [artworkKey] and it
/// resolves the cached artwork file through [artworkFileProvider], fades the
/// image in when the bytes are ready, and falls back to a themed gradient when
/// the album has no embedded art (or the cached file is missing). It never
/// throws and always occupies exactly [size] x [size], which keeps lists and
/// grids stable while artwork loads.
///
/// Pass [heroTag] on the two player surfaces (mini player and now playing) so
/// the artwork flies between them. Set [isPlaying] for a small animated
/// playing badge, or [vinyl] for a circular disc that spins while playing.
class AlbumArt extends ConsumerWidget {
  const AlbumArt({
    super.key,
    this.artworkKey,
    this.imageUrl,
    this.size = 52,
    this.borderRadius = 12,
    this.isPlaying = false,
    this.vinyl = false,
    this.placeholderIcon = Icons.music_note_rounded,
    this.fit = BoxFit.cover,
    this.heroTag,
    this.semanticLabel,
  });

  /// Cache key from `Song.artworkKey` (never a file path).
  final String? artworkKey;

  /// Optional HTTPS artwork URL for remote catalog tracks.
  final String? imageUrl;

  /// Side length of the square artwork.
  final double size;

  /// Corner radius. Ignored (half of [size]) when [vinyl] is true.
  final double borderRadius;

  /// Shows a subtle animated equalizer badge over the artwork.
  final bool isPlaying;

  /// Circular "vinyl disc" treatment. Spins while [isPlaying] is true.
  final bool vinyl;

  final IconData placeholderIcon;
  final BoxFit fit;

  /// Wraps the artwork in a [Hero] with this tag when non-null.
  final String? heroTag;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = artworkKey;
    final placeholder = _placeholder(context);

    Widget content;
    if (key == null || key.isEmpty) {
      final uri = Uri.tryParse(imageUrl ?? '');
      content = uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
          ? Image.network(
              uri.toString(),
              width: size,
              height: size,
              fit: fit,
              cacheWidth: (size * 2).round(),
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder;
    } else {
      content = ref
          .watch(artworkFileProvider(key))
          .when(
            data: (file) => file == null
                ? placeholder
                : _FileArtwork(
                    file: file,
                    size: size,
                    fit: fit,
                    placeholder: placeholder,
                  ),
            loading: () => placeholder,
            error: (_, _) => placeholder,
          );
    }

    final radius = vinyl ? size / 2 : borderRadius;
    final scheme = Theme.of(context).colorScheme;
    Widget art = SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: content,
      ),
    );

    if (vinyl && isPlaying) {
      art = _SpinningDisc(child: art);
    }

    // Hairline outline gives light artwork definition against any background.
    art = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: art,
    );

    if (isPlaying) {
      art = SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            art,
            Positioned(
              right: math.max(2.0, size * 0.045),
              bottom: math.max(2.0, size * 0.045),
              child: _PlayingBadge(size: math.max(18.0, size * 0.26)),
            ),
          ],
        ),
      );
    }

    if (heroTag != null) {
      art = Hero(tag: heroTag!, child: art);
    }

    final label = semanticLabel;
    if (label != null && label.isNotEmpty) {
      art = Semantics(label: label, image: true, child: art);
    }

    return art;
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(scheme.primary.withValues(alpha: 0.34), base),
            Color.alphaBlend(scheme.tertiary.withValues(alpha: 0.24), base),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          placeholderIcon,
          size: size * (vinyl ? 0.30 : 0.38),
          color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

/// Shared [Hero] tag for the player artwork of [songId].
///
/// The mini player and the full-screen player both use the same tag so the
/// artwork flies between them when the player opens or closes.
String albumArtHeroTag(String songId) => 'nmvibe-album-art-$songId';

/// Decodes the cached artwork file, fading in when the frame is ready.
class _FileArtwork extends StatelessWidget {
  const _FileArtwork({
    required this.file,
    required this.size,
    required this.fit,
    required this.placeholder,
  });

  final File file;
  final double size;
  final BoxFit fit;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (size * devicePixelRatio)
        .round()
        .clamp(48, 2048)
        .toInt();
    return Image.file(
      file,
      width: size,
      height: size,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: ThemeConstants.motionDuration(
            context,
            const Duration(milliseconds: 240),
          ),
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}

/// Slowly rotating disc used for the [AlbumArt.vinyl] variant.
class _SpinningDisc extends StatefulWidget {
  const _SpinningDisc({required this.child});

  final Widget child;

  @override
  State<_SpinningDisc> createState() => _SpinningDiscState();
}

class _SpinningDiscState extends State<_SpinningDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _controller, child: widget.child);
  }
}

/// Tiny animated "now playing" equalizer badge.
class _PlayingBadge extends StatefulWidget {
  const _PlayingBadge({required this.size});

  final double size;

  @override
  State<_PlayingBadge> createState() => _PlayingBadgeState();
}

class _PlayingBadgeState extends State<_PlayingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion && _controller.isAnimating) {
      _controller.stop();
    } else if (!reduceMotion && !_controller.isAnimating) {
      _controller.repeat();
    }
    final inner = widget.size * 0.56;
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: widget.size * 0.35,
            offset: Offset(0, widget.size * 0.08),
          ),
        ],
      ),
      padding: EdgeInsets.all(widget.size * 0.22),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: inner * 0.22,
                  height:
                      inner *
                      (reduceMotion
                          ? 0.55
                          : 0.28 +
                                0.72 *
                                    ((math.sin(
                                              _controller.value * 2 * math.pi +
                                                  i * 2.1,
                                            ) +
                                            1) /
                                        2)),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary,
                    borderRadius: BorderRadius.circular(inner * 0.1),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
