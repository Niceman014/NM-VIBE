import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/audio/audio_handler.dart';
import 'package:nm_vibe/core/utils/logger.dart';

/// One band of the device equalizer as seen by the settings UI.
///
/// Mirror of [EqualizerBandInfo] owned by the audio layer so the UI only has
/// to import this file. [gain] is the current value in decibels.
@immutable
class EqualizerBand {
  const EqualizerBand({
    required this.index,
    required this.centerFrequency,
    required this.minGain,
    required this.maxGain,
    required this.gain,
  });

  factory EqualizerBand.fromInfo(EqualizerBandInfo info) {
    return EqualizerBand(
      index: info.index,
      centerFrequency: info.centerFrequency,
      minGain: info.minGain,
      maxGain: info.maxGain,
      gain: info.gain,
    );
  }

  /// Zero based band index, low frequencies first.
  final int index;

  /// Centre frequency of the band in Hz.
  final double centerFrequency;

  /// Lowest allowed gain in dB (usually -15).
  final double minGain;

  /// Highest allowed gain in dB (usually +15).
  final double maxGain;

  /// Current gain in dB.
  final double gain;

  EqualizerBand copyWith({double? gain}) {
    return EqualizerBand(
      index: index,
      centerFrequency: centerFrequency,
      minGain: minGain,
      maxGain: maxGain,
      gain: gain ?? this.gain,
    );
  }

  /// [value] clamped to this band's supported gain range.
  double clampGain(double value) => value.clamp(minGain, maxGain).toDouble();

  @override
  String toString() =>
      'EqualizerBand(index: $index, centerFrequency: $centerFrequency, '
      'gain: $gain)';
}

/// Built-in equalizer presets and their curves.
///
/// Curves are expressed as five gains in dB, low band first. They are
/// resampled to whatever band count the device reports (Android devices
/// expose 3-10 bands depending on the OEM).
abstract final class EqualizerPresets {
  static const String flat = 'Flat';
  static const String bassBoost = 'Bass boost';
  static const String vocal = 'Vocal';
  static const String rock = 'Rock';
  static const String pop = 'Pop';
  static const String classical = 'Classical';

  /// Pseudo preset shown when the user has moved individual bands.
  static const String custom = 'Custom';

  /// Selectable presets, in display order. [custom] is not selectable.
  static const List<String> names = <String>[
    flat,
    bassBoost,
    vocal,
    rock,
    pop,
    classical,
  ];

  /// Canonical five band curves in dB, low frequencies first.
  static const Map<String, List<double>> _curves = <String, List<double>>{
    flat: <double>[0, 0, 0, 0, 0],
    bassBoost: <double>[8, 5, 1, 0, -1],
    vocal: <double>[-3, -1, 4, 3, 0],
    rock: <double>[5, 2, -1, 3, 4],
    pop: <double>[-1, 2, 4, 2, -1],
    classical: <double>[4, 2, -2, 3, 4],
  };

  /// Whether [preset] is a real preset (not [custom] and not unknown).
  static bool isKnown(String preset) => _curves.containsKey(preset);

  /// The [preset] curve resampled to [bandCount] bands.
  ///
  /// Unknown names fall back to [flat]; a band count of zero yields an empty
  /// list so callers can no-op safely on unsupported platforms.
  static List<double> gainsFor(String preset, int bandCount) {
    if (bandCount <= 0) return const <double>[];
    final curve = _curves[preset] ?? _curves[flat]!;
    if (bandCount == curve.length) return List<double>.of(curve);
    if (bandCount == 1) return <double>[curve[curve.length ~/ 2]];

    final gains = List<double>.filled(bandCount, 0);
    for (var i = 0; i < bandCount; i++) {
      final position = i * (curve.length - 1) / (bandCount - 1);
      final lower = position.floor();
      final upper = position.ceil().clamp(0, curve.length - 1).toInt();
      final fraction = position - lower;
      gains[i] = curve[lower] + (curve[upper] - curve[lower]) * fraction;
    }
    return gains;
  }

  /// Best matching named preset for [gains], or [custom] when nothing is
  /// close enough (all bands must be within [tolerance] dB of the curve).
  static String matchPreset(List<double> gains, {double tolerance = 0.25}) {
    if (gains.isEmpty) return custom;
    for (final name in names) {
      final curve = gainsFor(name, gains.length);
      var matches = true;
      for (var i = 0; i < gains.length; i++) {
        if ((curve[i] - gains[i]).abs() > tolerance) {
          matches = false;
          break;
        }
      }
      if (matches) return name;
    }
    return custom;
  }
}

/// Immutable snapshot of the equalizer for the settings sheet.
@immutable
class EqualizerState {
  const EqualizerState({
    this.supported = false,
    this.loading = false,
    this.enabled = true,
    this.bands = const <EqualizerBand>[],
    this.preset = EqualizerPresets.flat,
    this.error,
  });

  /// False on platforms without a system equalizer (Windows, iOS, web). Every
  /// controller method is a no-op in that case.
  final bool supported;

  /// True while the band list is being read from the platform.
  final bool loading;

  /// Whether the equalizer effect is switched on.
  final bool enabled;

  /// The device bands, low frequencies first. Empty until loaded (or when the
  /// platform has no equalizer).
  final List<EqualizerBand> bands;

  /// Name of the active preset: one of [EqualizerPresets.names] or
  /// [EqualizerPresets.custom].
  final String preset;

  /// Human readable error from the last failed operation, if any.
  final String? error;

  bool get hasBands => bands.isNotEmpty;
  bool get isReady => supported && !loading;
  bool get isCustom => preset == EqualizerPresets.custom;

  /// Representative gain range, taken from the first band (all Android bands
  /// share the same min/max decibel range). Safe defaults while loading.
  double get minGain => bands.isEmpty ? -12.0 : bands.first.minGain;
  double get maxGain => bands.isEmpty ? 12.0 : bands.first.maxGain;

  EqualizerState copyWith({
    bool? supported,
    bool? loading,
    bool? enabled,
    List<EqualizerBand>? bands,
    String? preset,
    String? error,
    bool clearError = false,
  }) {
    return EqualizerState(
      supported: supported ?? this.supported,
      loading: loading ?? this.loading,
      enabled: enabled ?? this.enabled,
      bands: bands ?? this.bands,
      preset: preset ?? this.preset,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Bridges [NmVibeAudioHandler]'s equalizer API to Riverpod.
///
/// On platforms without a system equalizer ([NmVibeAudioHandler
/// .supportsEqualizer] is false, e.g. Windows) the state reports
/// `supported: false`, no bands, and every method is a no-op — so the UI never
/// needs platform checks to read it.
class EqualizerController extends StateNotifier<EqualizerState> {
  EqualizerController({required NmVibeAudioHandler handler})
    : _handler = handler,
      super(
        EqualizerState(
          supported: handler.supportsEqualizer,
          enabled: handler.equalizerEnabled,
        ),
      );

  static const AppLogger _log = AppLogger('Equalizer');

  final NmVibeAudioHandler _handler;

  /// Reads the device bands. Safe to call more than once.
  Future<void> load() async {
    if (!mounted) return;
    if (!_handler.supportsEqualizer) {
      state = state.copyWith(loading: false);
      return;
    }
    state = state.copyWith(supported: true, loading: true, clearError: true);
    try {
      final infos = await _handler.equalizerBands();
      if (!mounted) return;
      final bands = infos.map(EqualizerBand.fromInfo).toList(growable: false);
      state = EqualizerState(
        supported: true,
        loading: false,
        enabled: _handler.equalizerEnabled,
        bands: List<EqualizerBand>.unmodifiable(bands),
        preset: EqualizerPresets.matchPreset(
          bands.map((band) => band.gain).toList(growable: false),
        ),
      );
    } catch (error, stackTrace) {
      _log.e('Could not load equalizer', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: 'Could not read the device equalizer.',
      );
    }
  }

  /// Alias of [load] for pull-to-refresh style UIs.
  Future<void> refresh() => load();

  /// Switches the equalizer effect on or off.
  Future<void> setEnabled(bool enabled) async {
    if (!mounted || !state.supported) return;
    state = state.copyWith(enabled: enabled, clearError: true);
    try {
      await _handler.setEqualizerEnabled(enabled);
    } catch (error, stackTrace) {
      _log.e('Could not toggle equalizer', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(error: 'Could not toggle the device equalizer.');
    }
  }

  Future<void> toggleEnabled() => setEnabled(!state.enabled);

  /// Moves one band to [gain] (clamped to the band's range) and marks the
  /// preset as [EqualizerPresets.custom].
  Future<void> setBandGain(int index, double gain) async {
    if (!mounted || !state.supported) return;
    final bands = state.bands;
    if (index < 0 || index >= bands.length) return;
    final band = bands[index];
    final clamped = band.clampGain(gain);
    final updated = List<EqualizerBand>.of(bands);
    updated[index] = band.copyWith(gain: clamped);
    state = state.copyWith(
      bands: List<EqualizerBand>.unmodifiable(updated),
      preset: EqualizerPresets.matchPreset(
        updated.map((item) => item.gain).toList(growable: false),
      ),
      clearError: true,
    );
    try {
      await _handler.setEqualizerGain(index, clamped);
    } catch (error, stackTrace) {
      _log.e('Could not apply equalizer gain', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(error: 'Could not change the equalizer band.');
    }
  }

  /// Applies a named preset ([EqualizerPresets.names]) to every band.
  ///
  /// [EqualizerPresets.custom] only changes the label and leaves the gains
  /// untouched. Unknown names are ignored.
  Future<void> setPreset(String preset) async {
    if (!mounted || !state.supported) return;
    if (preset == EqualizerPresets.custom) {
      state = state.copyWith(preset: EqualizerPresets.custom);
      return;
    }
    if (!EqualizerPresets.isKnown(preset)) return;
    final bands = state.bands;
    if (bands.isEmpty) return;

    final curve = EqualizerPresets.gainsFor(preset, bands.length);
    final updated = <EqualizerBand>[];
    for (var i = 0; i < bands.length; i++) {
      updated.add(bands[i].copyWith(gain: bands[i].clampGain(curve[i])));
    }
    state = state.copyWith(
      bands: List<EqualizerBand>.unmodifiable(updated),
      preset: preset,
      clearError: true,
    );
    try {
      for (var i = 0; i < updated.length; i++) {
        await _handler.setEqualizerGain(i, updated[i].gain);
      }
    } catch (error, stackTrace) {
      _log.e('Could not apply equalizer preset', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(error: 'Could not apply the preset.');
    }
  }

  /// Flattens every band back to 0 dB (the [EqualizerPresets.flat] curve).
  Future<void> reset() async {
    if (!mounted || !state.supported) return;
    final updated = state.bands
        .map((band) => band.copyWith(gain: 0))
        .toList(growable: false);
    state = state.copyWith(
      bands: List<EqualizerBand>.unmodifiable(updated),
      preset: EqualizerPresets.flat,
      clearError: true,
    );
    try {
      await _handler.resetEqualizer();
    } catch (error, stackTrace) {
      _log.e('Could not reset equalizer', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(error: 'Could not reset the equalizer.');
    }
  }
}

/// Global equalizer controller used by the Settings page.
///
/// Reading it on Windows is safe: the state is `supported: false` with no
/// bands, and every method is a no-op.
final equalizerControllerProvider =
    StateNotifierProvider<EqualizerController, EqualizerState>((ref) {
      final controller = EqualizerController(
        handler: ref.watch(audioHandlerProvider),
      );
      ref.onDispose(controller.dispose);
      unawaited(controller.load());
      return controller;
    });
