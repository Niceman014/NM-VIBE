import 'package:flutter/material.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';

/// Soft pulsing placeholder used while the first library snapshot is loading.
class SkeletonSongList extends StatelessWidget {
  const SkeletonSongList({super.key, this.count = 10});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _Pulse(
      child: Column(
        children: [
          for (var index = 0; index < count; index++) const _SkeletonSongRow(),
        ],
      ),
    );
  }
}

/// Pulsing grid placeholder for the albums / artists tabs.
class SkeletonCollectionGrid extends StatelessWidget {
  const SkeletonCollectionGrid({
    super.key,
    this.count = 8,
    this.crossAxisCount,
  });

  final int count;
  final int? crossAxisCount;

  @override
  Widget build(BuildContext context) {
    final columns =
        crossAxisCount ?? (MediaQuery.sizeOf(context).width >= 900 ? 4 : 2);
    final rows = <Widget>[];
    for (var index = 0; index < count; index += columns) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: ThemeConstants.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(
                            ThemeConstants.radiusMedium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacing8),
                    Container(
                      height: 12,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacing8),
                    Container(
                      height: 10,
                      width: 64,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacing24),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }
    return _Pulse(child: Column(children: rows));
  }
}

class _SkeletonSongRow extends StatelessWidget {
  const _SkeletonSongRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final block = BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacing8,
        vertical: 7,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: ThemeConstants.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 13, width: 160, decoration: block),
                const SizedBox(height: ThemeConstants.spacing8),
                Container(
                  height: 10,
                  width: 104,
                  decoration: block.copyWith(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 10, width: 34, decoration: block),
        ],
      ),
    );
  }
}

/// Applies a slow breathing opacity to placeholder content.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
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
    if (ThemeConstants.reduceMotion(context)) return widget.child;
    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.55,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
