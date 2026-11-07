import 'package:flutter/material.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';

/// Displays playback recovery actions without exposing low-level exception text.
class PlaybackErrorBanner extends StatelessWidget {
  const PlaybackErrorBanner({
    required this.error,
    required this.onRetry,
    this.onSkip,
    super.key,
  });

  final String error;
  final VoidCallback? onRetry;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing24,
        ThemeConstants.spacing4,
        ThemeConstants.spacing24,
        ThemeConstants.spacing4,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: ThemeConstants.spacing12,
          vertical: ThemeConstants.spacing8,
        ),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
                const SizedBox(width: ThemeConstants.spacing8),
                Expanded(
                  child: Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: ThemeConstants.spacing4),
            Wrap(
              spacing: ThemeConstants.spacing8,
              runSpacing: ThemeConstants.spacing4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                if (onSkip != null)
                  TextButton.icon(
                    onPressed: onSkip,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Skip'),
                  )
                else
                  Text(
                    'No next track is available.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
