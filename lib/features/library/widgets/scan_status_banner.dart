import 'package:flutter/material.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import '../controllers/scan_controller.dart';

/// Slim progress / error banner pinned under the library header while a scan is
/// running. Reads the shared [ScanState] contract from the scan controller.
class ScanStatusBanner extends StatelessWidget {
  const ScanStatusBanner({super.key, required this.state, this.onRetry});

  final ScanState state;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scanning = state.scanning;
    final error = state.error;

    if (!scanning && error == null) return const SizedBox.shrink();

    final isError = !scanning && error != null;
    final background = isError
        ? scheme.errorContainer.withValues(alpha: 0.55)
        : scheme.primaryContainer.withValues(alpha: 0.55);
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;

    final progressLabel = state.total > 0
        ? 'Scanning ${state.processed} of ${state.total}'
        : 'Scanning your library';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing16,
        ThemeConstants.spacing4,
        ThemeConstants.spacing16,
        ThemeConstants.spacing8,
      ),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(ThemeConstants.radiusMedium),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing16,
            ThemeConstants.spacing12,
            ThemeConstants.spacing12,
            ThemeConstants.spacing12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isError ? Icons.error_outline : Icons.auto_awesome,
                    size: 20,
                    color: foreground,
                  ),
                  const SizedBox(width: ThemeConstants.spacing8),
                  Expanded(
                    child: Text(
                      isError ? 'Scan failed' : progressLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (isError && onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(foregroundColor: foreground),
                      child: const Text('Retry'),
                    )
                  else if (scanning)
                    Text(
                      '${(state.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                ],
              ),
              if (scanning) ...[
                const SizedBox(height: ThemeConstants.spacing8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: state.total > 0 ? state.progress : null,
                    minHeight: 5,
                    color: foreground,
                    backgroundColor: foreground.withValues(alpha: 0.18),
                  ),
                ),
                if ((state.currentFile ?? '').isNotEmpty) ...[
                  const SizedBox(height: ThemeConstants.spacing8),
                  Text(
                    state.currentFile!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ] else if (error != null) ...[
                const SizedBox(height: ThemeConstants.spacing8),
                Text(
                  error,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
