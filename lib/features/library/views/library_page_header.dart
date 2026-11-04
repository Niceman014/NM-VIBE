part of 'library_page.dart';

extension _LibraryPageHeader on _LibraryPageState {
  // ------------------------------------------------------------------ header
  Widget _buildHeader({
    required BuildContext context,
    required List<Song> songs,
    required List<AlbumGroup> albums,
    required List<ArtistGroup> artists,
    required SongsSortMode sortMode,
    required bool sortAscending,
    required SettingsController settingsController,
    required ScanState scanState,
    required String query,
    required bool isLoading,
    required Future<void> Function() onScan,
    required Future<void> Function() onAddFolder,
    required VoidCallback onToggleFavourites,
    required ValueChanged<_LibraryTab> onTabChanged,
    required ValueChanged<String> onSearchChanged,
    required VoidCallback onClearSearch,
    required TextEditingController searchController,
    required FocusNode searchFocusNode,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stats = isLoading && songs.isEmpty
        ? 'Reading your music…'
        : '${songs.length} ${songs.length == 1 ? 'song' : 'songs'} · '
              '${albums.length} ${albums.length == 1 ? 'album' : 'albums'} · '
              '${artists.length} ${artists.length == 1 ? 'artist' : 'artists'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppConstants.appName.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 2.6,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
            const Spacer(),
            if (!PlatformInfo.usesMediaStoreScanner)
              _HeaderIconButton(
                tooltip: 'Add music folder',
                icon: Icons.create_new_folder_outlined,
                onPressed: scanState.scanning ? null : onAddFolder,
              ),
            _HeaderIconButton(
              tooltip: scanState.scanning ? 'Scanning…' : 'Scan library',
              icon: Icons.refresh_rounded,
              onPressed: scanState.scanning ? null : onScan,
              busy: scanState.scanning,
            ),
            _SortMenuButton(
              sortMode: sortMode,
              ascending: sortAscending,
              onSortModeChanged: settingsController.setSongsSortMode,
              onToggleAscending: () =>
                  settingsController.setSongsSortAscending(!sortAscending),
            ),
            _HeaderIconButton(
              tooltip: sortAscending ? 'Sort descending' : 'Sort ascending',
              icon: sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              onPressed: () =>
                  settingsController.setSongsSortAscending(!sortAscending),
            ),
          ],
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Text(
          'Your library',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Text(
          stats,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing16),
        _SearchField(
          controller: searchController,
          focusNode: searchFocusNode,
          query: query,
          onChanged: onSearchChanged,
          onClear: onClearSearch,
        ),
        const SizedBox(height: ThemeConstants.spacing12),
        Row(
          children: [
            Expanded(
              child: _SegmentedTabs(tab: _tab, onChanged: onTabChanged),
            ),
            const SizedBox(width: ThemeConstants.spacing8),
            _FavouritesPill(
              selected: _favouritesOnly,
              onTap: onToggleFavourites,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectionHeader(List<Song> selectAllCandidates) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelection,
        ),
        const SizedBox(width: ThemeConstants.spacing4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedIds.length == 1
                    ? '1 song selected'
                    : '${_selectedIds.length} songs selected',
                style: theme.textTheme.titleLarge,
              ),
              Text(
                'Tap songs to add or remove',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: selectAllCandidates.isEmpty
              ? null
              : () => _selectAll(selectAllCandidates),
        ),
      ],
    );
  }
}
