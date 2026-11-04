part of 'library_page.dart';

// --------------------------------------------------------------------- widgets
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search songs, artists, albums…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: onClear,
              ),
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.tab, required this.onChanged});

  final _LibraryTab tab;
  final ValueChanged<_LibraryTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: ThemeConstants.minimumTapTarget,
      padding: const EdgeInsets.all(ThemeConstants.spacing4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final value in _LibraryTab.values)
            Expanded(
              child: _Segment(
                label: switch (value) {
                  _LibraryTab.songs => 'Songs',
                  _LibraryTab.albums => 'Albums',
                  _LibraryTab.artists => 'Artists',
                },
                selected: tab == value,
                onTap: () => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: ThemeConstants.motionDuration(context, ThemeConstants.fast),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.shadow.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _FavouritesPill extends StatelessWidget {
  const _FavouritesPill({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Favourites',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: ThemeConstants.motionDuration(context, ThemeConstants.fast),
          height: ThemeConstants.minimumTapTarget,
          padding: const EdgeInsets.symmetric(
            horizontal: ThemeConstants.spacing16,
          ),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                size: 18,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: ThemeConstants.spacing8),
              Text(
                'Favourites',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function()? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return Tooltip(
        message: tooltip,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: SizedBox(
              width: ThemeConstants.spacing16,
              height: ThemeConstants.spacing16,
              child: CircularProgressIndicator(
                strokeWidth: ThemeConstants.spacing4,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
      );
    }
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 22),
      onPressed: onPressed == null ? null : () => onPressed!(),
    );
  }
}

class _SortMenuButton extends StatelessWidget {
  const _SortMenuButton({
    required this.sortMode,
    required this.ascending,
    required this.onSortModeChanged,
    required this.onToggleAscending,
  });

  final SongsSortMode sortMode;
  final bool ascending;
  final ValueChanged<SongsSortMode> onSortModeChanged;
  final VoidCallback onToggleAscending;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<Object>(
      tooltip: 'Sort songs',
      icon: const Icon(Icons.sort_rounded, size: 22),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value is SongsSortMode) {
          onSortModeChanged(value);
        } else {
          onToggleAscending();
        }
      },
      itemBuilder: (context) => [
        for (final mode in SongsSortMode.values)
          CheckedPopupMenuItem<SongsSortMode>(
            value: mode,
            checked: mode == sortMode,
            child: Text(mode.label),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: 'ascending',
          checked: ascending,
          child: Text(ascending ? 'Ascending' : 'Descending'),
        ),
      ],
    );
  }
}
