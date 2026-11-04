import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nm_vibe/core/scanner/artwork_service.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/core/theme/app_theme.dart';
import 'package:nm_vibe/features/player/controllers/palette_controller.dart';
import 'package:nm_vibe/features/player/views/equalizer_sheet.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';

/// Artwork service that never resolves a file, so [AlbumArt] can be exercised
/// without path_provider or any other plugin.
class _MissingArtworkService extends ArtworkService {
  @override
  Future<File?> fileForKey(String? key) async => null;
}

ColorScheme _scheme(Brightness brightness) => ColorScheme.fromSeed(
  seedColor: const Color(0xFF7C4DFF),
  brightness: brightness,
);

void main() {
  group('AppTheme', () {
    test('pure black dark surfaces keep foreground text readable', () {
      final scheme = AppTheme.dark(
        ThemeConstants.defaultSeed,
        pureBlack: true,
      ).colorScheme;

      expect(scheme.surface, ThemeConstants.pureBlackSurface);
      expect(_contrastRatio(scheme.onSurface, scheme.surface), greaterThan(7));
      expect(
        _contrastRatio(scheme.onSurfaceVariant, scheme.surface),
        greaterThan(4.5),
      );
    });

    testWidgets('motion duration is zero when the system reduces motion', (
      tester,
    ) async {
      late Duration duration;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              duration = ThemeConstants.motionDuration(
                context,
                ThemeConstants.medium,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(duration, Duration.zero);
    });
  });

  group('harmonizedAccent', () {
    for (final brightness in Brightness.values) {
      test('falls back to the theme primary without artwork ($brightness)', () {
        final scheme = _scheme(brightness);
        expect(harmonizedAccent(null, scheme), scheme.primary);
      });

      test('keeps artwork colours readable ($brightness)', () {
        final scheme = _scheme(brightness);
        const neonGreen = Color(0xFF00FF00);
        final accent = harmonizedAccent(neonGreen, scheme);
        final hsl = HSLColor.fromColor(accent);
        expect(hsl.lightness, inInclusiveRange(0.28, 0.66));
        expect(accent, isNot(neonGreen));
      });
    }
  });

  group('immersiveGradientColors', () {
    test('fades the artwork accent into the theme surface', () {
      final scheme = _scheme(Brightness.dark);
      final colors = immersiveGradientColors(const Color(0xFFE91E63), scheme);
      expect(colors, hasLength(4));
      expect(colors.last, scheme.surface);
      expect(colors.first, isNot(colors[1]));
    });

    test('works without artwork', () {
      final scheme = _scheme(Brightness.light);
      final colors = immersiveGradientColors(null, scheme);
      expect(colors, hasLength(4));
      expect(colors.last, scheme.surface);
    });
  });

  group('equalizer presets', () {
    test('flat is silent at every band count', () {
      expect(presetGains('Flat', 5), everyElement(0.0));
      expect(presetGains('Flat', 10), everyElement(0.0));
    });

    test('interpolates shapes to the reported band count', () {
      final gains = presetGains('Bass boost', 8);
      expect(gains, hasLength(8));
      expect(gains.first, greaterThan(gains.last));
      expect(gains.first, lessThanOrEqualTo(12));
      expect(gains.last, greaterThanOrEqualTo(-12));
    });

    test('formats centre frequencies', () {
      expect(equalizerFrequencyLabel(60), '60');
      expect(equalizerFrequencyLabel(910), '910');
      expect(equalizerFrequencyLabel(1000), '1k');
      expect(equalizerFrequencyLabel(1500), '1.5k');
      expect(equalizerFrequencyLabel(16000), '16k');
    });
  });

  group('AlbumArt', () {
    testWidgets('renders a fixed square placeholder without artwork', (
      tester,
    ) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: AlbumArt(
                  size: 56,
                  borderRadius: 16,
                  semanticLabel: 'Artwork for Test Song',
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(AlbumArt)), const Size(56, 56));
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    });

    testWidgets('falls back to the placeholder when the artwork is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            artworkServiceProvider.overrideWithValue(_MissingArtworkService()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AlbumArt(artworkKey: 'does-not-exist', size: 80),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.getSize(find.byType(AlbumArt)), const Size(80, 80));
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
