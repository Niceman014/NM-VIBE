import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/scanner/artwork_service.dart';

/// Extracts the dominant, most "alive" colour from a track's cached artwork.
///
/// Keyed by `Song.artworkKey`; pass `null` (or an empty string) for songs
/// without artwork and the provider resolves to `null`.
///
/// The provider deliberately returns `null` instead of inventing a colour when
/// there is no artwork: player surfaces then fall back to the theme seed via
/// [harmonizedAccent], which keeps NM VIBE's own identity on top of the
/// artwork-driven colour. Palette extraction never throws — a corrupt image or
/// a platform without an image codec simply produces `null`.
final artworkPaletteProvider = FutureProvider.family<Color?, String?>((
  ref,
  String? artworkKey,
) async {
  if (artworkKey == null || artworkKey.isEmpty) return null;

  final file = await ref.watch(artworkFileProvider(artworkKey).future);
  if (file == null) return null;

  try {
    final scheme = await ColorScheme.fromImageProvider(
      provider: FileImage(file),
      brightness: Brightness.dark,
    ).timeout(const Duration(seconds: 4));
    return scheme.primary;
  } catch (_) {
    // Corrupt/unsupported image or decode timeout: no artwork colour.
    return null;
  }
});

/// The colour player surfaces actually paint with.
///
/// Blends the artwork palette with the live Material 3 scheme so that any album
/// cover — however neon or muddy — still looks like it belongs to the app,
/// and clamps brightness so accents stay usable on both light and dark themes.
/// When there is no artwork colour this returns [ColorScheme.primary], which is
/// derived from the user's theme seed.
Color harmonizedAccent(Color? artworkPalette, ColorScheme scheme) {
  if (artworkPalette == null) return scheme.primary;

  final hsl = HSLColor.fromColor(artworkPalette);
  final dark = scheme.brightness == Brightness.dark;
  final lightness = dark
      ? hsl.lightness.clamp(0.34, 0.62).toDouble()
      : hsl.lightness.clamp(0.30, 0.54).toDouble();
  final softened = hsl
      .withSaturation(hsl.saturation.clamp(0.32, 0.88).toDouble())
      .withLightness(lightness)
      .toColor();

  // Keep a family resemblance to the app's own accent.
  return Color.lerp(softened, scheme.primary, 0.20)!;
}

/// Higher-contrast foreground for text/icons painted on [background].
Color foregroundOn(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}

/// Vertical gradient stops for the immersive player background.
///
/// The first colour is the artwork accent at full presence (top of the screen),
/// fading down into the theme surface so controls always sit on a calm base.
List<Color> immersiveGradientColors(Color? artworkPalette, ColorScheme scheme) {
  final accent = harmonizedAccent(artworkPalette, scheme);
  final dark = scheme.brightness == Brightness.dark;
  final top = Color.alphaBlend(
    accent.withValues(alpha: dark ? 0.48 : 0.30),
    scheme.surface,
  );
  final middle = Color.alphaBlend(
    accent.withValues(alpha: dark ? 0.20 : 0.14),
    scheme.surface,
  );
  return <Color>[top, middle, scheme.surface, scheme.surface];
}

/// A softly tinted surface used for inset cards on top of the player gradient.
Color playerPanelColor(Color? artworkPalette, ColorScheme scheme) {
  final accent = harmonizedAccent(artworkPalette, scheme);
  return Color.alphaBlend(
    accent.withValues(
      alpha: scheme.brightness == Brightness.dark ? 0.14 : 0.09,
    ),
    scheme.surfaceContainerHigh,
  );
}
