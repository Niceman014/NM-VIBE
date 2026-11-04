part of 'settings_page.dart';

// --------------------------------------------------------------------- pieces
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
    this.icon,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeConstants.spacing24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeConstants.spacing8,
              0,
              ThemeConstants.spacing8,
              ThemeConstants.spacing8,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: scheme.primary),
                  const SizedBox(width: ThemeConstants.spacing8),
                ],
                Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(ThemeConstants.radiusLarge),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  if (index > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  children[index],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: AnimatedContainer(
          duration: ThemeConstants.motionDuration(context, ThemeConstants.fast),
          width: ThemeConstants.minimumTapTarget,
          height: ThemeConstants.minimumTapTarget,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: ThemeConstants.readableOn(color),
                )
              : null,
        ),
      ),
    );
  }
}

/// Equalizer bottom sheet: presets plus per-band sliders.
class _EqualizerSheet extends ConsumerWidget {
  const _EqualizerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final eq = ref.watch(equalizerControllerProvider);
    final controller = ref.read(equalizerControllerProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing24,
            ThemeConstants.spacing4,
            ThemeConstants.spacing8,
            ThemeConstants.spacing8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Equalizer', style: theme.textTheme.titleLarge),
                    Text(
                      'Tune the sound to your headphones or speakers',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: eq.enabled,
                onChanged: eq.supported
                    ? (value) => controller.setEnabled(value)
                    : null,
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        if (!eq.supported)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(ThemeConstants.spacing24),
                child: Text(
                  'The equalizer is not available on this device.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                ThemeConstants.spacing24,
                0,
                ThemeConstants.spacing24,
                ThemeConstants.spacing24,
              ),
              children: [
                if (eq.loading) const LinearProgressIndicator(minHeight: 3),
                if (eq.error != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: ThemeConstants.spacing8,
                    ),
                    child: Text(
                      eq.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: ThemeConstants.spacing12),
                Wrap(
                  spacing: ThemeConstants.spacing8,
                  runSpacing: ThemeConstants.spacing8,
                  children: [
                    if (eq.isCustom)
                      Chip(
                        label: const Text('Custom'),
                        avatar: const Icon(Icons.tune_rounded, size: 16),
                        backgroundColor: scheme.primaryContainer.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    for (final preset in EqualizerPresets.names)
                      FilterChip(
                        label: Text(preset),
                        selected: eq.preset == preset,
                        onSelected: eq.loading
                            ? null
                            : (selected) => controller.setPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: ThemeConstants.spacing24),
                if (eq.loading && eq.bands.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: ThemeConstants.spacing32,
                    ),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (eq.bands.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: ThemeConstants.spacing32,
                    ),
                    child: Text(
                      'No equalizer bands were reported by this device.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (final band in eq.bands)
                    _EqualizerBandRow(
                      band: band,
                      enabled: eq.enabled && !eq.loading,
                      onChanged: (gain) =>
                          controller.setBandGain(band.index, gain),
                    ),
              ],
            ),
          ),
        if (eq.supported)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ThemeConstants.spacing24,
                ThemeConstants.spacing8,
                ThemeConstants.spacing24,
                ThemeConstants.spacing12,
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: eq.loading ? null : controller.reset,
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset to flat'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _EqualizerBandRow extends StatelessWidget {
  const _EqualizerBandRow({
    required this.band,
    required this.enabled,
    required this.onChanged,
  });

  final EqualizerBand band;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = band.gain.clamp(band.minGain, band.maxGain).toDouble();
    final frequency = band.centerFrequency >= 1000
        ? '${(band.centerFrequency / 1000).toStringAsFixed(band.centerFrequency >= 10000 ? 0 : 1)}k'
        : band.centerFrequency.toStringAsFixed(0);
    final gainLabel =
        '${band.gain > 0 ? '+' : ''}${band.gain.toStringAsFixed(1)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeConstants.spacing4),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              '$frequency Hz',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: band.minGain,
              max: band.maxGain,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '$gainLabel dB',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
