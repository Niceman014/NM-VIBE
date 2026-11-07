import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nm_vibe/data/downloads/offline_index.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/music_search_ranking.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/navigation/open_now_playing.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/shared/providers/music_providers.dart';
import 'package:nm_vibe/shared/widgets/empty_state.dart';
import 'package:nm_vibe/shared/widgets/song_tile.dart';

class DownloadsPage extends ConsumerStatefulWidget {
  const DownloadsPage({super.key});

  @override
  ConsumerState<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends ConsumerState<DownloadsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = ref.watch(songsProvider);
    final offline = ref.watch(offlineIndexProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloaded'),
        actions: [
          IconButton(
            tooltip: 'Shuffle downloaded songs',
            onPressed: () => _shuffle(songs.value ?? const <Song>[]),
            icon: const Icon(Icons.shuffle_rounded),
          ),
          IconButton(
            tooltip: 'Play downloaded songs',
            onPressed: () => _play(songs.value ?? const <Song>[]),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
      body: songs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Downloads unavailable',
          message: 'Could not read your library: $error',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(songsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (allSongs) => offline.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Download status unavailable',
            message: 'Could not check saved files: $error',
            action: FilledButton.icon(
              onPressed: () => ref.invalidate(offlineIndexProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
          data: (entries) => _buildContent(context, allSongs, entries),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Song> allSongs,
    List<OfflineTrackEntry> entries,
  ) {
    final savedSongs = allSongs.where((song) => song.isDownloaded).toList();
    final availability = <String, OfflineTrackEntry>{
      for (final entry in entries) entry.record.id: entry,
    };
    final query = normalizeMusicSearchText(_query);
    final visible = savedSongs
        .where((song) {
          if (query.isEmpty) return true;
          final haystack = normalizeMusicSearchText(
            '${song.displayTitle} ${song.displayArtist} ${song.displayAlbum}',
          );
          return haystack.contains(query) ||
              query.split(' ').every(haystack.contains);
        })
        .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search downloaded songs',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        Expanded(
          child: savedSongs.isEmpty
              ? const EmptyState(
                  icon: Icons.download_for_offline_outlined,
                  title: 'No downloaded music yet',
                  message:
                      'Tracks saved for offline listening will appear here.',
                )
              : visible.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No downloaded songs found',
                  message: 'Try a different title, artist, or album name.',
                  action: TextButton.icon(
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Clear search'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final song = visible[index];
                    final entry = availability[song.id];
                    final playable = entry?.canPlayOffline ?? false;
                    final status = _availabilityLabel(entry);
                    return SongTile(
                      song: song,
                      onTap: playable
                          ? () => _play(visible, initialIndex: index)
                          : null,
                      subtitle: '${song.displayArtist} · $status',
                      showDuration: false,
                      showActions: playable,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            playable
                                ? Icons.offline_pin_rounded
                                : Icons.warning_amber_rounded,
                            color: playable
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                          IconButton(
                            tooltip: 'Remove offline copy',
                            onPressed: () => _remove(song),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _availabilityLabel(OfflineTrackEntry? entry) {
    if (entry == null ||
        entry.availability == OfflineFileAvailability.missing) {
      return 'File missing';
    }
    if (entry.availability == OfflineFileAvailability.sizeMismatch) {
      final actual = entry.actualSizeBytes;
      final expected = entry.record.sizeBytes;
      return actual == null
          ? 'File size mismatch'
          : 'File size mismatch · ${formatFileSize(actual)} found, ${formatFileSize(expected)} expected';
    }
    return 'Available offline · ${formatFileSize(entry.record.sizeBytes)}';
  }

  Future<void> _play(List<Song> songs, {int initialIndex = 0}) async {
    final entries = ref.read(offlineIndexProvider).value ?? const [];
    final availableIds = entries
        .where((entry) => entry.canPlayOffline)
        .map((entry) => entry.record.id)
        .toSet();
    final playable = songs
        .where((song) => song.isDownloaded && availableIds.contains(song.id))
        .toList(growable: false);
    if (playable.isEmpty) return;
    final selected = songs.elementAtOrNull(initialIndex);
    final safeIndex = selected == null
        ? 0
        : playable.indexWhere((song) => song.id == selected.id);
    await playSongsAndOpen(
      context,
      ref,
      playable,
      initialIndex: safeIndex < 0 ? 0 : safeIndex,
    );
  }

  Future<void> _shuffle(List<Song> songs) async {
    final entries = ref.read(offlineIndexProvider).value ?? const [];
    final availableIds = entries
        .where((entry) => entry.canPlayOffline)
        .map((entry) => entry.record.id)
        .toSet();
    final playable =
        songs
            .where(
              (song) => song.isDownloaded && availableIds.contains(song.id),
            )
            .toList(growable: true)
          ..shuffle(Random());
    await playSongsAndOpen(context, ref, playable);
  }

  Future<void> _remove(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove offline copy?'),
        content: Text(
          '“${song.displayTitle}” will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(downloadStorageProvider).deleteRecord(song.id);
      final updated = song.copyWith(
        filePath: song.streamUrl ?? song.filePath,
        fileSize: 0,
        isDownloaded: false,
      );
      await ref.read(libraryRepositoryProvider).updateSong(updated);
      ref.invalidate(offlineIndexProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed “${song.displayTitle}” offline copy.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove offline copy: $error')),
        );
      }
    }
  }
}
