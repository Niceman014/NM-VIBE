import 'package:flutter/material.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';

/// Calm, roomy empty state used across the library, playlists and favourites
/// surfaces. One primary action, at most one secondary action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    this.secondaryAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  final Widget? secondaryAction;

  /// Drops the oversized icon tile; useful inside narrow sheets.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final useCompact = compact;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: useCompact
              ? ThemeConstants.spacing24
              : ThemeConstants.spacing32,
          vertical: useCompact
              ? ThemeConstants.spacing24
              : ThemeConstants.spacing32,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!useCompact) ...[
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primaryContainer,
                        scheme.tertiaryContainer,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(
                      ThemeConstants.radiusLarge,
                    ),
                  ),
                  child: Icon(icon, size: 40, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: ThemeConstants.spacing24),
              ] else ...[
                Icon(icon, size: 32, color: scheme.primary),
                const SizedBox(height: ThemeConstants.spacing12),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: useCompact
                    ? theme.textTheme.titleLarge
                    : theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (action != null || secondaryAction != null) ...[
                const SizedBox(height: ThemeConstants.spacing24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: ThemeConstants.spacing12,
                  runSpacing: ThemeConstants.spacing12,
                  children: [?action, ?secondaryAction],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
