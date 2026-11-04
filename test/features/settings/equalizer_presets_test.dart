import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/features/settings/controllers/equalizer_controller.dart';

void main() {
  group('EqualizerPresets', () {
    test('exposes the expected selectable presets', () {
      expect(EqualizerPresets.names, <String>[
        EqualizerPresets.flat,
        EqualizerPresets.bassBoost,
        EqualizerPresets.vocal,
        EqualizerPresets.rock,
        EqualizerPresets.pop,
        EqualizerPresets.classical,
      ]);
      expect(EqualizerPresets.names, isNot(contains(EqualizerPresets.custom)));
    });

    test('flat curve is silence at every band count', () {
      for (var bands = 1; bands <= 10; bands++) {
        expect(
          EqualizerPresets.gainsFor(EqualizerPresets.flat, bands),
          everyElement(0.0),
          reason: 'bands: $bands',
        );
      }
    });

    test('bass boost lifts low frequencies and not the top band', () {
      final gains = EqualizerPresets.gainsFor(EqualizerPresets.bassBoost, 5);
      expect(gains.first, greaterThan(0));
      expect(gains.first, greaterThan(gains.last));
    });

    test('resamples curves to any device band count', () {
      for (var bands = 1; bands <= 10; bands++) {
        for (final name in EqualizerPresets.names) {
          final gains = EqualizerPresets.gainsFor(name, bands);
          expect(gains.length, bands, reason: '$name x $bands bands');
          for (final gain in gains) {
            expect(gain, inInclusiveRange(-10.0, 10.0));
          }
        }
      }
    });

    test('empty band count yields an empty curve (unsupported platform)', () {
      expect(EqualizerPresets.gainsFor(EqualizerPresets.bassBoost, 0), isEmpty);
      expect(EqualizerPresets.gainsFor(EqualizerPresets.flat, -1), isEmpty);
    });

    test('unknown preset names fall back to flat', () {
      expect(EqualizerPresets.isKnown('Nope'), isFalse);
      expect(EqualizerPresets.gainsFor('Nope', 4), everyElement(0.0));
    });

    test('matchPreset recognises a freshly applied curve', () {
      for (final name in EqualizerPresets.names) {
        final gains = EqualizerPresets.gainsFor(name, 5);
        expect(EqualizerPresets.matchPreset(gains), name);
      }
    });

    test('matchPreset returns Custom once a band is tweaked', () {
      final gains = EqualizerPresets.gainsFor(EqualizerPresets.rock, 5);
      gains[2] += 2;
      expect(EqualizerPresets.matchPreset(gains), EqualizerPresets.custom);
    });

    test('matchPreset returns Custom for empty gains', () {
      expect(
        EqualizerPresets.matchPreset(const <double>[]),
        EqualizerPresets.custom,
      );
    });
  });

  group('EqualizerState', () {
    test('default state is an unsupported no-op', () {
      const state = EqualizerState();
      expect(state.supported, isFalse);
      expect(state.loading, isFalse);
      expect(state.hasBands, isFalse);
      expect(state.isReady, isFalse);
      expect(state.bands, isEmpty);
      expect(state.preset, EqualizerPresets.flat);
      expect(state.error, isNull);
      // Fallback range keeps UI sliders sane before bands load.
      expect(state.minGain, lessThan(0));
      expect(state.maxGain, greaterThan(0));
    });

    test('copyWith can set and clear the error', () {
      const state = EqualizerState();
      final failed = state.copyWith(error: 'boom');
      expect(failed.error, 'boom');
      expect(failed.copyWith(clearError: true).error, isNull);
    });

    test('equalizer band clamps gains to its own range', () {
      const band = EqualizerBand(
        index: 0,
        centerFrequency: 60,
        minGain: -15,
        maxGain: 15,
        gain: 0,
      );
      expect(band.clampGain(3), 3);
      expect(band.clampGain(99), 15);
      expect(band.clampGain(-99), -15);
      expect(band.copyWith(gain: 4).gain, 4);
      expect(band.copyWith(gain: 4).centerFrequency, 60);
    });
  });
}
