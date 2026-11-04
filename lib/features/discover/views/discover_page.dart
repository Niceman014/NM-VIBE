import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nm_vibe/core/utils/logger.dart';
import 'package:nm_vibe/shared/providers/music_providers.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/sources/music_source.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';
import 'package:nm_vibe/shared/widgets/loading_skeleton.dart';
import 'discover_error_message.dart';

const _logger = AppLogger('Discover');

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final TextEditingController _searchController = TextEditingController();
  late final MusicRepository _musicRepository;
  List<MusicTrack> _tracks = const <MusicTrack>[];
  Timer? _debounce;
  String? _error;
  bool _loading = false;
  int _searchGeneration = 0;
  final Set<DownloadTask> _activeDownloads = <DownloadTask>{};

  @override
  void initState() {
    super.initState();
    _musicRepository = ref.read(musicRepositoryProvider);
    if (_musicRepository.isConfigured) unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final task in _activeDownloads) {
      unawaited(task.cancel());
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (!_musicRepository.isConfigured) return;
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracks = await _musicRepository.search(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (error, stackTrace) {
      _logger.e('Search failed', error, stackTrace);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _error = discoverErrorMessage(error);
      });
    }
  }

  void _onSearchChanged(String query) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _play(MusicTrack track) async {
    await ref
        .read(playerControllerProvider.notifier)
        .playSong(
          track.toSong(),
          context: _tracks.map((item) => item.toSong()).toList(),
        );
  }

  Future<void> _addToQueue(MusicTrack track) async {
    await ref
        .read(playerControllerProvider.notifier)
        .addToQueue(track.toSong());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added “${track.title}” to the queue.')),
      );
    }
  }

  Future<void> _playNext(MusicTrack track) async {
    await ref.read(playerControllerProvider.notifier).playNext(track.toSong());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“${track.title}” will play next.')),
      );
    }
  }

  Future<void> _download(MusicTrack track) async {
    final progress = ValueNotifier<(int, int?)>((0, null));
    var progressClosed = false;
    final operation = _musicRepository.startDownload(
      track,
      onProgress: (received, total) {
        if (!progressClosed) progress.value = (received, total);
      },
    );
    _activeDownloads.add(operation);
    var dialogDismissed = false;
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Saving ${track.title}'),
        content: ValueListenableBuilder<(int, int?)>(
          valueListenable: progress,
          builder: (context, value, _) {
            final received = value.$1;
            final total = value.$2;
            final fraction = total == null || total <= 0
                ? null
                : (received / total).clamp(0.0, 1.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: fraction),
                const SizedBox(height: ThemeConstants.spacing12),
                Text(
                  total == null
                      ? '${(received / (1024 * 1024)).toStringAsFixed(1)} MB'
                      : '${(received / (1024 * 1024)).toStringAsFixed(1)} / ${(total / (1024 * 1024)).toStringAsFixed(1)} MB',
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await operation.cancel();
              if (dialogContext.mounted) {
                dialogDismissed = true;
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    try {
      final file = await operation.result;
      if (!dialogDismissed && mounted) {
        dialogDismissed = true;
        Navigator.of(context).pop();
        await dialog;
      }
      final downloaded = track.toSong().copyWith(
        filePath: file.path,
        fileSize: await file.length(),
        modifiedAt: await file.lastModified(),
        isDownloaded: true,
      );
      await ref.read(libraryRepositoryProvider).updateSong(downloaded);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved “${track.title}” for offline listening.'),
          ),
        );
      }
    } on DownloadCancelled {
      // The user cancelled; the downloader removes its partial file.
    } catch (error) {
      if (!dialogDismissed && mounted) {
        dialogDismissed = true;
        Navigator.of(context).pop();
        await dialog;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save track: $error')));
      }
    } finally {
      progressClosed = true;
      progress.dispose();
      _activeDownloads.remove(operation);
    }
  }

  Future<void> _openTrack(MusicTrack track) async {
    final url = track.pageUrl;
    if (url == null) return;
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open source page.')),
      );
    }
  }

  Future<void> _openLicense(MusicTrack track) async {
    final url = track.licenseUrl;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final configured = _musicRepository.isConfigured;
    final jamendoConfigured = _musicRepository.isSourceConfigured('jamendo');

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ThemeConstants.spacing24,
                ThemeConstants.spacing24,
                ThemeConstants.spacing24,
                ThemeConstants.spacing12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DISCOVER',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: ThemeConstants.spacing8),
                  Text(
                    'Find your next favourite',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: ThemeConstants.spacing12),
                  TextField(
                    controller: _searchController,
                    enabled: configured,
                    onChanged: _onSearchChanged,
                    onSubmitted: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists and albums',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                _search('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!jamendoConfigured)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing24,
                  0,
                  ThemeConstants.spacing24,
                  ThemeConstants.spacing8,
                ),
                child: Text(
                  'Jamendo: Online search is not configured. Set BACKEND_URL in a debug build to use a local backend.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (!configured)
              const Expanded(child: _SetupNotice())
            else if (_error != null)
              Expanded(
                child: _MessageState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load music',
                  message: _error!,
                  actionLabel: 'Try again',
                  onAction: () => _search(_searchController.text),
                ),
              )
            else if (_loading && _tracks.isEmpty)
              const Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(ThemeConstants.spacing16),
                    child: SkeletonSongList(count: 6),
                  ),
                ),
              )
            else if (_tracks.isEmpty)
              const Expanded(
                child: _MessageState(
                  icon: Icons.music_off_rounded,
                  title: 'No tracks found',
                  message: 'Try a different title, artist or genre.',
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => _search(_searchController.text),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      ThemeConstants.spacing12,
                      0,
                      ThemeConstants.spacing12,
                      ThemeConstants.spacing24,
                    ),
                    itemCount: _tracks.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _tracks.length) {
                        return const _CatalogAttribution();
                      }
                      final track = _tracks[index];
                      return _MusicTrackTile(
                        key: ValueKey<String>('${track.sourceId}:${track.id}'),
                        track: track,
                        credit: _musicRepository.attributionFor(track),
                        onPlay: () => _play(track),
                        onOpen: track.pageUrl == null
                            ? null
                            : () => _openTrack(track),
                        onOpenLicense: track.licenseUrl == null
                            ? null
                            : () => _openLicense(track),
                        onAddToQueue: () => _addToQueue(track),
                        onPlayNext: () => _playNext(track),
                        onDownload: _musicRepository.canDownload(track)
                            ? () => _download(track)
                            : null,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MusicTrackTile extends StatelessWidget {
  const _MusicTrackTile({
    super.key,
    required this.track,
    required this.credit,
    required this.onPlay,
    required this.onOpen,
    required this.onOpenLicense,
    required this.onAddToQueue,
    required this.onPlayNext,
    required this.onDownload,
  });

  final MusicTrack track;
  final String credit;
  final VoidCallback onPlay;
  final VoidCallback? onOpen;
  final VoidCallback? onOpenLicense;
  final VoidCallback onAddToQueue;
  final VoidCallback onPlayNext;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConstants.spacing4,
        vertical: ThemeConstants.spacing4,
      ),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(ThemeConstants.spacing8),
            child: Row(
              children: [
                AlbumArt(
                  imageUrl: track.artworkUrl,
                  size: 54,
                  borderRadius: 14,
                  semanticLabel: 'Artwork for ${track.title}',
                ),
                const SizedBox(width: ThemeConstants.spacing12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: ThemeConstants.spacing4),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (track.album.isNotEmpty)
                        Text(
                          track.album,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        credit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (onOpen != null || onOpenLicense != null)
                        Wrap(
                          spacing: ThemeConstants.spacing8,
                          children: [
                            if (onOpen != null)
                              InkWell(
                                onTap: onOpen,
                                child: Text(
                                  'View item',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            if (onOpenLicense != null)
                              InkWell(
                                onTap: onOpenLicense,
                                child: Text(
                                  'License',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: ThemeConstants.spacing4),
                IconButton(
                  tooltip: 'Play ${track.title}',
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_circle_fill_rounded, size: 30),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More track actions',
                  onSelected: (action) {
                    switch (action) {
                      case 'queue':
                        onAddToQueue();
                      case 'next':
                        onPlayNext();
                      case 'open':
                        onOpen?.call();
                      case 'download':
                        onDownload?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'queue',
                      child: Text('Add to queue'),
                    ),
                    const PopupMenuItem(
                      value: 'next',
                      child: Text('Play next'),
                    ),
                    if (onDownload != null)
                      const PopupMenuItem(
                        value: 'download',
                        child: Text('Save for offline listening'),
                      ),
                    if (onOpen != null)
                      const PopupMenuItem(
                        value: 'open',
                        child: Text('Open source item'),
                      ),
                  ],
                  icon: const Icon(Icons.more_vert_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogAttribution extends StatelessWidget {
  const _CatalogAttribution();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ThemeConstants.spacing12,
        ThemeConstants.spacing16,
        ThemeConstants.spacing12,
        ThemeConstants.spacing12,
      ),
      child: Text(
        'Each result credits its creator and links to the source item and license when available.',
        textAlign: TextAlign.center,
        style: style,
      ),
    );
  }
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice();

  @override
  Widget build(BuildContext context) {
    return const _MessageState(
      icon: Icons.music_note_rounded,
      title: 'Online music is not configured',
      message:
          'Online search is not configured. Set BACKEND_URL when building the app '
          'to enable Jamendo search through your local or hosted backend.',
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConstants.spacing24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: ThemeConstants.spacing12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: ThemeConstants.spacing16),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
