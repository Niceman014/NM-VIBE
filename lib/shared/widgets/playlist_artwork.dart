import 'package:flutter/material.dart';

import 'package:nm_vibe/shared/widgets/album_art.dart';
import 'package:nm_vibe/data/models/song_model.dart';

/// Small mosaic cover for a playlist: up to four album covers, with a soft
/// gradient fallback when the playlist has no artwork yet.
class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    super.key,
    required this.songs,
    this.size = 56,
    this.borderRadius = 14,
  });

  final List<Song> songs;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final keys = <String?>[];
    for (final song in songs) {
      final key = song.artworkKey;
      if (key != null && key.isNotEmpty && !keys.contains(key)) {
        keys.add(key);
      }
      if (keys.length == 4) break;
    }

    if (keys.isEmpty) {
      return _GradientFallback(size: size, borderRadius: borderRadius);
    }

    // Tiny covers read as noise; fall back to the first cover below ~64px.
    if (size < 64) {
      return AlbumArt(
        artworkKey: keys.first,
        size: size,
        borderRadius: borderRadius,
      );
    }

    final slots = <String?>[...keys.take(4)];
    while (slots.length < 4) {
      slots.add(null);
    }
    const gap = 2.0;
    final cell = (size - gap) / 2;

    Widget cellFor(String? key) {
      if (key == null) {
        return Container(
          width: cell,
          height: cell,
          color: scheme.surfaceContainerHighest,
        );
      }
      return AlbumArt(artworkKey: key, size: cell, borderRadius: 0);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: Column(
          children: [
            Row(
              children: [
                cellFor(slots[0]),
                const SizedBox(width: gap),
                cellFor(slots[1]),
              ],
            ),
            const SizedBox(height: gap),
            Row(
              children: [
                cellFor(slots[2]),
                const SizedBox(width: gap),
                cellFor(slots[3]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientFallback extends StatelessWidget {
  const _GradientFallback({required this.size, required this.borderRadius});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.queue_music_rounded,
        size: size * 0.42,
        color: scheme.onPrimaryContainer,
      ),
    );
  }
}
