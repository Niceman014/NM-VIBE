import 'package:flutter/material.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';
import 'package:nm_vibe/data/models/playlist_model.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/widgets/playlist_artwork.dart';

/// Prompts for a playlist name. Returns the trimmed name, or null when the
/// user cancels.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  String initialName = '',
  String title = 'New playlist',
  String confirmLabel = 'Create',
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => _PlaylistNameDialog(
      initialName: initialName,
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

/// Bottom sheet that adds [songIds] to an existing playlist or spins up a new
/// one on the spot.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<String> songIds,
}) {
  if (songIds.isEmpty) return Future<void>.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AddToPlaylistSheet(songIds: songIds),
  );
}

/// Bottom sheet that lets the user pick library songs to append to a playlist.
Future<void> showSongPickerSheet(
  BuildContext context,
  WidgetRef ref, {
  required Playlist playlist,
  required List<String> existingSongIds,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _SongPickerSheet(
        playlistId: playlist.id,
        playlistName: playlist.name,
        existingSongIds: existingSongIds.toSet(),
      ),
    ),
  );
}

class _AddToPlaylistSheet extends ConsumerStatefulWidget {
  const _AddToPlaylistSheet({required this.songIds});

  final List<String> songIds;

  @override
  ConsumerState<_AddToPlaylistSheet> createState() =>
      _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends ConsumerState<_AddToPlaylistSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playlists = ref.watch(playlistsProvider).value ?? const <Playlist>[];
    final songs = ref.watch(songsProvider).value ?? const <Song>[];
    final songCount = widget.songIds.length;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          ThemeConstants.spacing16,
          0,
          ThemeConstants.spacing16,
          ThemeConstants.spacing16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ThemeConstants.spacing8,
                ThemeConstants.spacing4,
                ThemeConstants.spacing8,
                ThemeConstants.spacing12,
              ),
              child: Text(
                songCount == 1
                    ? 'Add song to playlist'
                    : 'Add $songCount songs',
                style: theme.textTheme.titleLarge,
              ),
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: theme.colorScheme.primaryContainer.withValues(
                alpha: 0.55,
              ),
              leading: Icon(
                Icons.add_rounded,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              title: Text(
                'New playlist',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: _busy ? null : _createNewPlaylist,
            ),
            if (playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing16,
                  ThemeConstants.spacing24,
                  ThemeConstants.spacing16,
                  ThemeConstants.spacing8,
                ),
                child: Text(
                  'No playlists yet — create one and these songs land inside.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              const SizedBox(height: ThemeConstants.spacing12),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing8,
                  0,
                  ThemeConstants.spacing8,
                  ThemeConstants.spacing4,
                ),
                child: Text(
                  'YOUR PLAYLISTS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              for (final playlist in playlists)
                _PlaylistTargetTile(
                  playlist: playlist,
                  songs: songs,
                  enabled: !_busy,
                  onTap: () => _addToPlaylist(playlist),
                ),
            ],
            if (_busy) ...[
              const SizedBox(height: ThemeConstants.spacing12),
              const LinearProgressIndicator(minHeight: 2),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _createNewPlaylist() async {
    final name = await showPlaylistNameDialog(context);
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .createPlaylist(name.trim(), songIds: widget.songIds);
      messenger.showSnackBar(
        SnackBar(content: Text('Created “${name.trim()}”')),
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create playlist: $error')),
      );
    }
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .addSongsToPlaylist(playlist.id, widget.songIds);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.songIds.length == 1
                ? 'Added to “${playlist.name}”'
                : 'Added ${widget.songIds.length} songs to “${playlist.name}”',
          ),
        ),
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update playlist: $error')),
      );
    }
  }
}

class _PlaylistTargetTile extends StatelessWidget {
  const _PlaylistTargetTile({
    required this.playlist,
    required this.songs,
    required this.enabled,
    required this.onTap,
  });

  final Playlist playlist;
  final List<Song> songs;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = resolvePlaylistSongs(playlist, songs);
    return ListTile(
      enabled: enabled,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacing8,
        vertical: ThemeConstants.spacing4,
      ),
      leading: PlaylistArtwork(songs: resolved, size: 48, borderRadius: 12),
      title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(trackCountLabel(resolved.length)),
      trailing: Icon(
        Icons.add_circle_outline_rounded,
        color: theme.colorScheme.primary,
      ),
      onTap: onTap,
    );
  }
}

class _SongPickerSheet extends ConsumerStatefulWidget {
  const _SongPickerSheet({
    required this.playlistId,
    required this.playlistName,
    required this.existingSongIds,
  });

  final String playlistId;
  final String playlistName;
  final Set<String> existingSongIds;

  @override
  ConsumerState<_SongPickerSheet> createState() => _SongPickerSheetState();
}

class _SongPickerSheetState extends ConsumerState<_SongPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songs = ref.watch(sortedSongsProvider);
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? songs
        : songs
              .where(
                (song) =>
                    song.displayTitle.toLowerCase().contains(query) ||
                    song.displayArtist.toLowerCase().contains(query) ||
                    song.displayAlbum.toLowerCase().contains(query),
              )
              .toList(growable: false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing24,
            0,
            ThemeConstants.spacing12,
            ThemeConstants.spacing8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add songs', style: theme.textTheme.titleLarge),
                    const SizedBox(height: ThemeConstants.spacing4),
                    Text(
                      widget.playlistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ThemeConstants.spacing24,
          ),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search your library',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(height: ThemeConstants.spacing8),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _query.trim().isEmpty
                        ? 'Your library is empty.'
                        : 'No songs match “${_query.trim()}”.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    ThemeConstants.spacing12,
                    ThemeConstants.spacing4,
                    ThemeConstants.spacing12,
                    ThemeConstants.spacing12,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final song = filtered[index];
                    final alreadyAdded = widget.existingSongIds.contains(
                      song.id,
                    );
                    final selected = _selectedIds.contains(song.id);
                    return _PickableSongRow(
                      song: song,
                      selected: selected,
                      disabled: alreadyAdded || _busy,
                      alreadyAdded: alreadyAdded,
                      onTap: () {
                        setState(() {
                          if (!_selectedIds.add(song.id)) {
                            _selectedIds.remove(song.id);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                ThemeConstants.spacing24,
                ThemeConstants.spacing12,
                ThemeConstants.spacing24,
                ThemeConstants.spacing12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _selectedIds.isEmpty
                          ? 'Pick songs to add'
                          : trackCountLabel(_selectedIds.length),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _selectedIds.isEmpty || _busy
                        ? null
                        : _addSelected,
                    icon: _busy
                        ? const SizedBox(
                            width: ThemeConstants.spacing16,
                            height: ThemeConstants.spacing16,
                            child: CircularProgressIndicator(
                              strokeWidth: ThemeConstants.spacing4,
                            ),
                          )
                        : const Icon(Icons.playlist_add_rounded),
                    label: Text(_busy ? 'Adding…' : 'Add'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addSelected() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(libraryRepositoryProvider)
          .addSongsToPlaylist(widget.playlistId, _selectedIds.toList());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _selectedIds.length == 1
                ? 'Added 1 song to “${widget.playlistName}”'
                : 'Added ${_selectedIds.length} songs to “${widget.playlistName}”',
          ),
        ),
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not add songs: $error')),
      );
    }
  }
}

class _PickableSongRow extends StatelessWidget {
  const _PickableSongRow({
    required this.song,
    required this.selected,
    required this.disabled,
    required this.alreadyAdded,
    required this.onTap,
  });

  final Song song;
  final bool selected;
  final bool disabled;
  final bool alreadyAdded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Opacity(
      opacity: alreadyAdded ? 0.55 : 1,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ThemeConstants.spacing8,
              vertical: ThemeConstants.spacing8,
            ),
            child: Row(
              children: [
                Checkbox(
                  value: alreadyAdded ? true : selected,
                  onChanged: disabled ? null : (_) => onTap(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: ThemeConstants.spacing8),
                AlbumArt(
                  artworkKey: song.artworkKey,
                  size: 44,
                  borderRadius: 10,
                ),
                const SizedBox(width: ThemeConstants.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        alreadyAdded
                            ? 'Already in playlist'
                            : song.displayArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ThemeConstants.spacing8),
                Text(
                  formatDuration(song.duration),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.initialName,
    required this.title,
    required this.confirmLabel,
  });

  final String initialName;
  final String title;
  final String confirmLabel;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 60,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: ThemeConstants.spacing4),
          Text(
            'Give it a name you will recognise.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canSave ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
