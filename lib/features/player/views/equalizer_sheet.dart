import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/audio/audio_handler.dart';
import 'package:nm_vibe/core/platform/platform_info.dart';

/// Opens the Android equalizer as a bottom sheet from the player.
Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height;
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.86),
        child: const SingleChildScrollView(
          padding: EdgeInsets.only(bottom: ThemeConstants.spacing16),
          child: EqualizerSheet(),
        ),
      );
    },
  );
}

/// Preset shapes, expressed in dB across five anchor bands (low to high).
/// They are interpolated to whatever band count the device exposes.
const Map<String, List<double>> equalizerPresetShapes = <String, List<double>>{
  'Flat': <double>[0, 0, 0, 0, 0],
  'Bass boost': <double>[7, 5, 2, 0, -1],
  'Vocal': <double>[-2, 1, 4, 3, 1],
  'Rock': <double>[4, 2, -1, 2, 4],
  'Pop': <double>[-1, 2, 3, 2, -1],
};

/// Interpolates a preset shape to [bandCount] bands, clamped to the device's
/// gain range. Pure function so it can be unit-tested without plugins.
List<double> presetGains(
  String preset,
  int bandCount, {
  double minGain = -12,
  double maxGain = 12,
}) {
  if (bandCount <= 0) return const <double>[];
  final shape = equalizerPresetShapes[preset] ?? equalizerPresetShapes['Flat']!;
  if (bandCount == 1) {
    return <double>[shape.first.clamp(minGain, maxGain).toDouble()];
  }
  final gains = <double>[];
  for (var band = 0; band < bandCount; band++) {
    final position = band / (bandCount - 1) * (shape.length - 1);
    final lower = position.floor();
    final upper = math.min(shape.length - 1, lower + 1);
    final fraction = position - lower;
    final value = shape[lower] * (1 - fraction) + shape[upper] * fraction;
    gains.add(value.clamp(minGain, maxGain).toDouble());
  }
  return gains;
}

/// Formats an equalizer centre frequency for a compact axis label.
String equalizerFrequencyLabel(double hertz) {
  if (hertz >= 1000) {
    final kilo = hertz / 1000;
    final text = kilo >= 10
        ? kilo.toStringAsFixed(0)
        : kilo.toStringAsFixed(kilo == kilo.roundToDouble() ? 0 : 1);
    return '${text}k';
  }
  return hertz.round().toString();
}

/// Equalizer UI: enabled switch, presets and one vertical band slider per band.
class EqualizerSheet extends ConsumerStatefulWidget {
  const EqualizerSheet({super.key});

  @override
  ConsumerState<EqualizerSheet> createState() => _EqualizerSheetState();
}

class _EqualizerSheetState extends ConsumerState<EqualizerSheet> {
  bool _loading = true;
  bool _unsupported = false;
  bool _enabled = true;
  String _preset = 'Flat';
  List<EqualizerBandInfo> _bands = const <EqualizerBandInfo>[];
  final Map<int, double> _gains = <int, double>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final handler = ref.read(audioHandlerProvider);
    if (!handler.supportsEqualizer) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unsupported = true;
      });
      return;
    }
    final bands = await handler.equalizerBands();
    if (!mounted) return;
    setState(() {
      _bands = bands;
      _enabled = handler.equalizerEnabled;
      _gains
        ..clear()
        ..addEntries(bands.map((band) => MapEntry(band.index, band.gain)));
      _loading = false;
    });
  }

  NmVibeAudioHandler get _handler => ref.read(audioHandlerProvider);

  Future<void> _setEnabled(bool enabled) async {
    setState(() => _enabled = enabled);
    await _handler.setEqualizerEnabled(enabled);
  }

  Future<void> _applyPreset(String preset) async {
    setState(() {
      _preset = preset;
      final gains = presetGains(
        preset,
        _bands.length,
        minGain: _minimumGain,
        maxGain: _maximumGain,
      );
      for (var i = 0; i < _bands.length; i++) {
        _gains[_bands[i].index] = gains[i];
      }
    });
    for (var i = 0; i < _bands.length; i++) {
      await _handler.setEqualizerGain(
        _bands[i].index,
        _gains[_bands[i].index]!,
      );
    }
  }

  Future<void> _reset() async {
    setState(() {
      _preset = 'Flat';
      for (final band in _bands) {
        _gains[band.index] = 0;
      }
    });
    await _handler.resetEqualizer();
  }

  double get _minimumGain => _bands.isEmpty ? -12 : _bands.first.minGain;

  double get _maximumGain => _bands.isEmpty ? 12 : _bands.first.maxGain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_unsupported) {
      return _EqualizerUnsupported(theme: theme);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing24,
        0,
        ThemeConstants.spacing24,
        ThemeConstants.spacing8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Equalizer', style: theme.textTheme.titleLarge),
                    const SizedBox(height: ThemeConstants.spacing4),
                    Text(
                      'Shape the sound of everything you play.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: _enabled, onChanged: _loading ? null : _setEnabled),
            ],
          ),
          const SizedBox(height: ThemeConstants.spacing12),
          if (_loading)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_bands.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(
                child: Text('This device did not report any equalizer bands.'),
              ),
            )
          else ...[
            Wrap(
              spacing: ThemeConstants.spacing8,
              runSpacing: ThemeConstants.spacing4,
              children: [
                for (final preset in equalizerPresetShapes.keys)
                  ChoiceChip(
                    label: Text(preset),
                    selected: _preset == preset,
                    onSelected: _enabled ? (_) => _applyPreset(preset) : null,
                  ),
              ],
            ),
            const SizedBox(height: ThemeConstants.spacing16),
            SizedBox(
              height: 244,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final band in _bands)
                    Expanded(
                      child: _EqualizerBandSlider(
                        band: band,
                        gain: _gains[band.index] ?? band.gain,
                        minGain: band.minGain,
                        maxGain: band.maxGain,
                        enabled: _enabled,
                        onChanged: (value) {
                          setState(() => _gains[band.index] = value);
                        },
                        onChangeEnd: (value) {
                          _handler.setEqualizerGain(band.index, value);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: ThemeConstants.spacing8),
            Row(
              children: [
                Text(
                  'Preamp style tuning',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _enabled ? _reset : null,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ],
          if (!PlatformInfo.supportsEqualizer)
            Padding(
              padding: const EdgeInsets.only(top: ThemeConstants.spacing8),
              child: Text(
                'Equalizer is only available on Android.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EqualizerBandSlider extends StatelessWidget {
  const _EqualizerBandSlider({
    required this.band,
    required this.gain,
    required this.minGain,
    required this.maxGain,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final EqualizerBandInfo band;
  final double gain;
  final double minGain;
  final double maxGain;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final divisions = math.max(1, ((maxGain - minGain) / 0.5).round());
    return IgnorePointer(
      ignoring: !enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Column(
          children: [
            Text(
              '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: gain.abs() < 0.1
                    ? scheme.onSurfaceVariant
                    : scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: gain.clamp(minGain, maxGain).toDouble(),
                  min: minGain,
                  max: maxGain,
                  divisions: divisions,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
            ),
            const SizedBox(height: ThemeConstants.spacing4),
            Text(
              equalizerFrequencyLabel(band.centerFrequency),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EqualizerUnsupported extends StatelessWidget {
  const _EqualizerUnsupported({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing24,
        0,
        ThemeConstants.spacing24,
        ThemeConstants.spacing32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.equalizer_rounded,
            size: 44,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: ThemeConstants.spacing12),
          Text('Equalizer unavailable', style: theme.textTheme.titleMedium),
          const SizedBox(height: ThemeConstants.spacing8),
          Text(
            'This device did not expose an audio equalizer. Everything else '
            'still plays normally.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
