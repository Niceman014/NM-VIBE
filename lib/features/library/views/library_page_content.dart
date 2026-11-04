part of 'library_page.dart';

extension _LibraryPageContent on _LibraryPageState {
  // ----------------------------------------------------------------- content
  List<Widget> _buildContent({
    required BuildContext context,
    required double sidePadding,
    required List<Song> songs,
    required List<Song> favourites,
    required List<Song> visibleSongs,
    required List<AlbumGroup> visibleAlbums,
    required List<ArtistGroup> visibleArtists,
    required List<Song> searchResults,
    required bool searching,
    required String query,
    required bool isLoading,
    required Object? error,
    required String? currentSongId,
    required bool isPlaying,
  }) {
    if (isLoading && songs.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              sidePadding,
              ThemeConstants.spacing8,
              sidePadding,
              0,
            ),
            child: const SkeletonSongList(),
          ),
        ),
      ];
    }

    if (error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load your library',
            message: '$error',
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(songsProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
        ),
      ];
    }

    if (searching) {
      if (searchResults.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message: 'Nothing in your library matches “${query.trim()}”.',
              action: TextButton(
                onPressed: _clearSearch,
                child: const Text('Clear search'),
              ),
            ),
          ),
        ];
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              sidePadding + ThemeConstants.spacing8,
              ThemeConstants.spacing8,
              sidePadding,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${searchResults.length} ${searchResults.length == 1 ? 'result' : 'results'} for “${query.trim()}”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(onPressed: _clearSearch, child: const Text('Clear')),
              ],
            ),
          ),
        ),
        _songListSliver(
          songs: searchResults,
          sidePadding: sidePadding,
          currentSongId: currentSongId,
          isPlaying: isPlaying,
          subtitleFor: (song) => song.displayAlbum,
        ),
      ];
    }

    if (songs.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.graphic_eq_rounded,
            title: 'Your vibe starts here',
            message:
                'Add the music you already own. NM VIBE reads your files, '
                'artwork and playlists. Your local library stays on this device.',
            action: FilledButton.icon(
              onPressed: _scanLibrary,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Scan my music'),
            ),
            secondaryAction: PlatformInfo.usesMediaStoreScanner
                ? null
                : OutlinedButton.icon(
                    onPressed: _addFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add folder'),
                  ),
          ),
        ),
      ];
    }

    switch (_tab) {
      case _LibraryTab.songs:
        if (_favouritesOnly && favourites.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'No favourites yet',
                message:
                    'Tap the heart in any song menu — or long-press songs and '
                    'use the selection bar — to build your favourites.',
                action: FilledButton.tonal(
                  onPressed: _showAllSongs,
                  child: const Text('Show all songs'),
                ),
              ),
            ),
          ];
        }
        return [
          SliverPadding(
            padding: const EdgeInsets.only(top: ThemeConstants.spacing4),
            sliver: _songListSliver(
              songs: visibleSongs,
              sidePadding: sidePadding,
              currentSongId: currentSongId,
              isPlaying: isPlaying,
              subtitleFor: (song) => song.displayArtist,
            ),
          ),
        ];
      case _LibraryTab.albums:
        if (visibleAlbums.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.album_outlined,
                title: 'No albums here',
                message: _favouritesOnly
                    ? 'Favourite a few songs and their albums will show up.'
                    : 'Albums appear once your songs have album tags.',
                action: _favouritesOnly
                    ? FilledButton.tonal(
                        onPressed: _showAllSongs,
                        child: const Text('Show all albums'),
                      )
                    : null,
              ),
            ),
          ];
        }
        return [
          _collectionGrid(
            sidePadding: sidePadding,
            childCount: visibleAlbums.length,
            crossAxisExtent: 230,
            childAspectRatio: 0.72,
            itemBuilder: (context, index) {
              final album = visibleAlbums[index];
              final isCurrentAlbum = album.songs.any(
                (song) => song.id == currentSongId,
              );
              return AlbumCard(
                album: album,
                isCurrent: isCurrentAlbum,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AlbumDetailPage(album: album),
                  ),
                ),
              );
            },
          ),
        ];
      case _LibraryTab.artists:
        if (visibleArtists.isEmpty) {
          return [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.person_outline_rounded,
                title: 'No artists here',
                message: _favouritesOnly
                    ? 'Favourite a few songs and their artists will show up.'
                    : 'Artists appear once your songs have artist tags.',
              ),
            ),
          ];
        }
        return [
          _collectionGrid(
            sidePadding: sidePadding,
            childCount: visibleArtists.length,
            crossAxisExtent: 210,
            childAspectRatio: 0.69,
            itemBuilder: (context, index) {
              final artist = visibleArtists[index];
              final isCurrentArtist = artist.songs.any(
                (song) => song.id == currentSongId,
              );
              return ArtistCard(
                artist: artist,
                isCurrent: isCurrentArtist,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArtistDetailPage(artist: artist),
                  ),
                ),
              );
            },
          ),
        ];
    }
  }

  Widget _songListSliver({
    required List<Song> songs,
    required double sidePadding,
    required String? currentSongId,
    required bool isPlaying,
    required String? Function(Song song) subtitleFor,
  }) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: sidePadding - ThemeConstants.spacing8,
      ),
      sliver: SliverList.builder(
        itemCount: songs.length,
        itemBuilder: (context, index) {
          final song = songs[index];
          return SongTile(
            song: song,
            selected: _selectedIds.contains(song.id),
            selectionMode: _selectionMode,
            isCurrent: song.id == currentSongId,
            isPlaying: isPlaying,
            subtitle: subtitleFor(song),
            onTap: () => _onSongTap(songs, index, song),
            onLongPress: () => _startSelection(song),
          );
        },
      ),
    );
  }

  Widget _collectionGrid({
    required double sidePadding,
    required int childCount,
    required double crossAxisExtent,
    required double childAspectRatio,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: sidePadding),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: crossAxisExtent,
          crossAxisSpacing: ThemeConstants.spacing12,
          mainAxisSpacing: ThemeConstants.spacing8,
          childAspectRatio: childAspectRatio,
        ),
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: childCount,
        ),
      ),
    );
  }
}
