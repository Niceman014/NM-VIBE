import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/constants/app_constants.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/data/models/library_groups.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/storage/settings_service.dart';
import 'package:nm_vibe/core/platform/platform_info.dart';
import 'package:nm_vibe/shared/navigation/open_now_playing.dart';
import '../controllers/scan_controller.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/widgets/add_to_playlist_sheet.dart';
import '../widgets/collection_cards.dart';
import 'package:nm_vibe/shared/widgets/empty_state.dart';
import 'package:nm_vibe/shared/widgets/loading_skeleton.dart';
import '../widgets/scan_status_banner.dart';
import '../widgets/selection_bar.dart';
import 'package:nm_vibe/shared/widgets/song_tile.dart';
import 'album_detail_page.dart';
import 'artist_detail_page.dart';

part 'library_page_header.dart';
part 'library_page_content.dart';
part 'library_page_widgets.dart';

enum _LibraryTab { songs, albums, artists }

/// The heart of NM VIBE: a roomy, artwork-forward library with songs, albums,
/// artists and favourites, inline search, sorting and multi-select actions.
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  _LibraryTab _tab = _LibraryTab.songs;
  bool _favouritesOnly = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ helpers
  double _sidePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 1000) return ((width - 960) / 2).clamp(24.0, 480.0);
    return width >= 600 ? 24 : 16;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    _onSearchChanged('');
  }

  void _startSelection(Song song) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(song.id);
    });
  }

  void _toggleSelected(String songId) {
    setState(() {
      if (!_selectedIds.add(songId)) _selectedIds.remove(songId);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelection() {
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _showAllSongs() => setState(() => _favouritesOnly = false);

  void _selectAll(List<Song> songs) {
    setState(() {
      _selectionMode = true;
      _selectedIds
        ..clear()
        ..addAll(songs.map((song) => song.id));
    });
  }

  void _onSongTap(List<Song> songs, int index, Song song) {
    if (_selectionMode) {
      _toggleSelected(song.id);
      return;
    }
    unawaited(playSongsAndOpen(context, ref, songs, initialIndex: index));
  }

  // --------------------------------------------------------------- async work
  Future<void> _scanLibrary() async {
    try {
      await ref.read(scanControllerProvider.notifier).scanLibrary();
    } catch (error) {
      _showSnack('Scan failed: $error');
    }
  }

  Future<void> _addFolder() async {
    try {
      await ref.read(scanControllerProvider.notifier).addFolder();
    } catch (error) {
      _showSnack('Could not add a folder: $error');
    }
  }

  Future<void> _favouriteSelected(List<Song> selectedSongs) async {
    if (selectedSongs.isEmpty) return;
    final repository = ref.read(libraryRepositoryProvider);
    final shouldFavourite = !selectedSongs.every((song) => song.isFavorite);
    for (final song in selectedSongs) {
      if (song.isFavorite == shouldFavourite) continue;
      await repository.updateSong(song.copyWith(isFavorite: shouldFavourite));
    }
    _exitSelection();
    _showSnack(
      shouldFavourite
          ? 'Added ${selectedSongs.length} to favourites'
          : 'Removed ${selectedSongs.length} from favourites',
    );
  }

  Future<void> _queueSelected(List<Song> selectedSongs) async {
    if (selectedSongs.isEmpty) return;
    final player = ref.read(playerControllerProvider.notifier);
    for (final song in selectedSongs) {
      await player.addToQueue(song);
    }
    _exitSelection();
    _showSnack(
      selectedSongs.length == 1
          ? 'Added 1 song to the queue'
          : 'Added ${selectedSongs.length} songs to the queue',
    );
  }

  Future<void> _addSelectedToPlaylist(List<Song> selectedSongs) async {
    if (selectedSongs.isEmpty) return;
    await showAddToPlaylistSheet(
      context,
      ref,
      songIds: selectedSongs.map((song) => song.id).toList(growable: false),
    );
    _exitSelection();
  }

  // -------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final sidePadding = _sidePadding(context);

    final songs = ref.watch(sortedSongsProvider);
    final favourites = ref.watch(favoriteSongsProvider);
    final albums = ref.watch(albumsProvider);
    final artists = ref.watch(artistsProvider);
    final isLoading = ref.watch(isLoadingLibraryProvider);
    final error = ref.watch(libraryErrorProvider);
    final sortOptions = ref.watch(
      settingsControllerProvider.select(
        (settings) => (settings.songsSortMode, settings.songsSortAscending),
      ),
    );
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final currentSongId = ref.watch(
      playerControllerProvider.select((state) => state.current?.id),
    );
    final isPlaying = ref.watch(
      playerControllerProvider.select((state) => state.playing),
    );
    final scanState = ref.watch(scanControllerProvider);
    final query = ref.watch(searchQueryProvider);
    final searchResults = ref.watch(searchResultsProvider);

    ref.listen<ScanState>(scanControllerProvider, (previous, next) {
      if (previous == null || !previous.scanning || next.scanning) return;
      if (next.error != null) {
        _showSnack('Scan failed: ${next.error}');
        return;
      }
      if (!next.hasLibraryChanges) return;
      final parts = <String>[
        if (next.added > 0) '${next.added} added',
        if (next.updated > 0) '${next.updated} updated',
        if (next.removed > 0) '${next.removed} removed',
      ];
      if (parts.isNotEmpty) {
        _showSnack('Library updated — ${parts.join(' · ')}');
      }
    });

    final searching = query.trim().isNotEmpty;
    final visibleSongs = searching
        ? searchResults
        : (_favouritesOnly ? favourites : songs);
    final visibleAlbums = _favouritesOnly ? groupAlbums(favourites) : albums;
    final visibleArtists = _favouritesOnly ? groupArtists(favourites) : artists;
    final selectedSongs = songs
        .where((song) => _selectedIds.contains(song.id))
        .toList(growable: false);
    final selectAllCandidates = searching
        ? searchResults
        : (_favouritesOnly ? favourites : songs);

    final contentSlivers = _buildContent(
      context: context,
      sidePadding: sidePadding,
      songs: songs,
      favourites: favourites,
      visibleSongs: visibleSongs,
      visibleAlbums: visibleAlbums,
      visibleArtists: visibleArtists,
      searchResults: searchResults,
      searching: searching,
      query: query,
      isLoading: isLoading,
      error: error,
      currentSongId: currentSongId,
      isPlaying: isPlaying,
    );

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    sidePadding,
                    _selectionMode
                        ? ThemeConstants.spacing8
                        : ThemeConstants.spacing8,
                    sidePadding,
                    _selectionMode
                        ? ThemeConstants.spacing4
                        : ThemeConstants.spacing8,
                  ),
                  child: _selectionMode
                      ? _buildSelectionHeader(selectAllCandidates)
                      : _buildHeader(
                          context: context,
                          songs: songs,
                          albums: albums,
                          artists: artists,
                          sortMode: sortOptions.$1,
                          sortAscending: sortOptions.$2,
                          settingsController: settingsController,
                          scanState: scanState,
                          query: query,
                          isLoading: isLoading,
                          onScan: _scanLibrary,
                          onAddFolder: _addFolder,
                          onToggleFavourites: () => setState(
                            () => _favouritesOnly = !_favouritesOnly,
                          ),
                          onTabChanged: (tab) => setState(() => _tab = tab),
                          onSearchChanged: _onSearchChanged,
                          onClearSearch: _clearSearch,
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                        ),
                ),
              ),
              if (!_selectionMode)
                SliverToBoxAdapter(
                  child: ScanStatusBanner(
                    state: scanState,
                    onRetry: _scanLibrary,
                  ),
                ),
              ...contentSlivers,
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _selectionMode ? 132 : ThemeConstants.spacing32,
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_selectionMode,
              child: AnimatedSlide(
                offset: _selectionMode ? Offset.zero : const Offset(0, 1.4),
                duration: ThemeConstants.motionDuration(
                  context,
                  ThemeConstants.medium,
                ),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _selectionMode ? 1 : 0,
                  duration: ThemeConstants.motionDuration(
                    context,
                    ThemeConstants.fast,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: LibrarySelectionBar(
                        count: _selectedIds.length,
                        favouriteActive:
                            selectedSongs.isNotEmpty &&
                            selectedSongs.every((song) => song.isFavorite),
                        onFavourite: () => _favouriteSelected(selectedSongs),
                        onAddToPlaylist: () =>
                            _addSelectedToPlaylist(selectedSongs),
                        onQueue: () => _queueSelected(selectedSongs),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
