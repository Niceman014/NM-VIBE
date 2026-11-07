import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nm_vibe/core/utils/logger.dart';
import 'package:nm_vibe/shared/providers/music_providers.dart';
import 'package:nm_vibe/data/downloads/download_task.dart';
import 'package:nm_vibe/data/downloads/download_manager.dart';
import 'package:nm_vibe/data/downloads/offline_index.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/repositories/music_search_ranking.dart';
import 'package:nm_vibe/data/sources/music_source.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/shared/navigation/open_downloads.dart';
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
  String? _loadMoreError;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _currentPage = 0;
  int _searchGeneration = 0;
  List<String> _failedSourceIds = const <String>[];
  final Map<String, DownloadJob> _activeDownloads = <String, DownloadJob>{};

  @override
  void initState() {
    super.initState();
    _musicRepository = ref.read(musicRepositoryProvider);
    if (_musicRepository.isConfigured) unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final task in _activeDownloads.values) {
      unawaited(task.cancel());
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query, {int? generation}) async {
    if (!_musicRepository.isConfigured) return;
    _debounce?.cancel();
    final requestGeneration = generation ?? ++_searchGeneration;
    if (requestGeneration != _searchGeneration) return;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _hasMore = false;
      _currentPage = 0;
      _tracks = const <MusicTrack>[];
      _error = null;
      _loadMoreError = null;
      _failedSourceIds = const <String>[];
    });
    try {
      final page = await _musicRepository.searchPage(
        query,
        page: 1,
        onSourceUpdate: (update) {
          if (!mounted || requestGeneration != _searchGeneration) return;
          if (update.tracks.isEmpty && !update.failed) return;
          setState(() {
            if (update.tracks.isNotEmpty) {
              _tracks = rankMusicTracks(
                query,
                deduplicateMusicTracks([..._tracks, ...update.tracks]),
              );
            }
            if (update.failed) {
              _failedSourceIds = <String>{
                ..._failedSourceIds,
                update.sourceId,
              }.toList(growable: false);
            }
          });
        },
      );
      if (!mounted || requestGeneration != _searchGeneration) return;
      setState(() {
        _tracks = page.tracks;
        _currentPage = 1;
        _hasMore = page.hasMore;
        _failedSourceIds = page.failedSourceIds;
        _loading = false;
      });
    } catch (error, stackTrace) {
      _logger.e('Search failed', error, stackTrace);
      if (!mounted || requestGeneration != _searchGeneration) return;
      setState(() {
        _loading = false;
        _error = discoverErrorMessage(error);
      });
    }
  }

  void _onSearchChanged(String query) {
    final generation = ++_searchGeneration;
    _debounce?.cancel();
    setState(() {
      _loading = _musicRepository.isConfigured;
      _loadingMore = false;
      _hasMore = false;
      _currentPage = 0;
      _tracks = const <MusicTrack>[];
      _error = null;
      _loadMoreError = null;
      _failedSourceIds = const <String>[];
    });
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_search(query, generation: generation)),
    );
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final generation = _searchGeneration;
    final nextPage = _currentPage + 1;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    try {
      final page = await _musicRepository.searchPage(
        _searchController.text,
        page: nextPage,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _tracks = rankMusicTracks(
          _searchController.text,
          deduplicateMusicTracks([..._tracks, ...page.tracks]),
        );
        _currentPage = nextPage;
        _hasMore = page.hasMore;
        _failedSourceIds = <String>{
          ..._failedSourceIds,
          ...page.failedSourceIds,
        }.toList(growable: false);
        _loadingMore = false;
      });
    } catch (error, stackTrace) {
      _logger.e('Loading more search results failed', error, stackTrace);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = discoverErrorMessage(error);
      });
    }
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

  Future<void> _download(
    MusicTrack track, {
    bool retry = false,
    bool repair = false,
  }) async {
    final manager = ref.read(downloadManagerProvider);
    late final DownloadJob job;
    try {
      final taskId = '${track.sourceId}:${track.id}';
      job = repair
          ? await manager.redownload(track)
          : retry
          ? await manager.retry(taskId)
          : await manager.enqueue(track);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save track: $error')));
      }
      return;
    }
    if (!mounted) {
      unawaited(job.cancel());
      return;
    }
    _activeDownloads[job.id] = job;
    var dialogDismissed = false;
    final dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('Saving ${track.title}'),
        content: StreamBuilder<ManagedDownloadTask?>(
          stream: manager.watchTask(job.id),
          initialData: manager.task(job.id),
          builder: (context, snapshot) {
            final state = snapshot.data;
            final received = state?.receivedBytes ?? 0;
            final total = state?.totalBytes;
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
              await job.cancel();
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
      await job.result;
      ref.invalidate(offlineIndexProvider);
      if (!dialogDismissed && mounted) {
        dialogDismissed = true;
        Navigator.of(context).pop();
        await dialog;
      }
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
      _activeDownloads.remove(job.id);
    }
  }

  String _downloadUnavailableReason(MusicTrack track) {
    if (!_musicRepository.canDownload(track)) {
      if (!track.downloadAllowed) {
        return 'This item’s licence does not permit an offline copy.';
      }
      return 'This music source does not permit offline downloads.';
    }
    final uri = Uri.tryParse(track.downloadUrl ?? '');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'A secure download URL is not available for this track.';
    }
    return 'This track cannot currently be saved offline.';
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
    final songs = ref.watch(songsProvider).value ?? const [];
    final downloadedSongIds = songs
        .where((song) => song.isDownloaded)
        .map((song) => song.id)
        .toSet();
    final offlineEntries = ref.watch(offlineIndexProvider).value ?? const [];
    final offlineById = <String, OfflineTrackEntry>{
      for (final entry in offlineEntries) entry.record.id: entry,
    };
    final manager = ref.read(downloadManagerProvider);

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
            if (_failedSourceIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing24,
                  0,
                  ThemeConstants.spacing24,
                  ThemeConstants.spacing8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Some music sources could not be searched. Results may be incomplete.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _search(_searchController.text),
                      child: const Text('Retry sources'),
                    ),
                  ],
                ),
              ),
            if (_loading && _tracks.isNotEmpty)
              const LinearProgressIndicator(minHeight: 2),
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
                        if (_loadingMore) {
                          return const _SearchFooter(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (_loadMoreError != null) {
                          return _SearchFooter(
                            child: Column(
                              children: [
                                Text(
                                  _loadMoreError!,
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: _loadMore,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (_hasMore) {
                          return _SearchFooter(
                            child: OutlinedButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(Icons.expand_more_rounded),
                              label: const Text('Load more'),
                            ),
                          );
                        }
                        return const _CatalogAttribution();
                      }
                      final track = _tracks[index];
                      final taskId = '${track.sourceId}:${track.id}';
                      final songId = track.toSong().id;
                      final savedEntry = offlineById[songId];
                      final isSavedAndValid =
                          downloadedSongIds.contains(songId) &&
                          savedEntry?.canPlayOffline == true;
                      final permitted =
                          _musicRepository.canDownload(track) &&
                          _hasSecureDownloadUrl(track);
                      return StreamBuilder<ManagedDownloadTask?>(
                        stream: manager.watchTask(taskId),
                        initialData: manager.task(taskId),
                        builder: (context, snapshot) {
                          final task = snapshot.data;
                          final working =
                              task?.status == ManagedDownloadStatus.waiting ||
                              task?.status == ManagedDownloadStatus.downloading;
                          final failed =
                              task?.status == ManagedDownloadStatus.failed;
                          final downloaded = isSavedAndValid;
                          final status = _downloadStatus(
                            task,
                            savedEntry,
                            downloaded,
                          );
                          return _MusicTrackTile(
                            key: ValueKey<String>(taskId),
                            track: track,
                            credit: _musicRepository.attributionFor(track),
                            downloadStatus:
                                status ??
                                (permitted ? null : 'Not available offline'),
                            downloadProgress: task?.progress,
                            onPlay: () => _play(track),
                            onOpen: track.pageUrl == null
                                ? null
                                : () => _openTrack(track),
                            onOpenLicense: track.licenseUrl == null
                                ? null
                                : () => _openLicense(track),
                            onAddToQueue: () => _addToQueue(track),
                            onPlayNext: () => _playNext(track),
                            onDownloadAction:
                                downloaded || working || !permitted
                                ? null
                                : () => _download(
                                    track,
                                    retry: failed && savedEntry == null,
                                    repair: savedEntry != null && !downloaded,
                                  ),
                            downloadActionLabel:
                                failed || savedEntry != null && !downloaded
                                ? 'Retry download'
                                : 'Save offline',
                            onCancelDownload: working
                                ? () => _cancelDownload(manager, taskId)
                                : null,
                            onOpenDownloads: downloaded || savedEntry != null
                                ? () => openDownloads(context)
                                : null,
                            onDownloadUnavailable:
                                !downloaded && !working && !permitted
                                ? () => ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            _downloadUnavailableReason(track),
                                          ),
                                        ),
                                      )
                                : null,
                          );
                        },
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

  bool _hasSecureDownloadUrl(MusicTrack track) {
    final uri = Uri.tryParse(track.downloadUrl ?? '');
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  String? _downloadStatus(
    ManagedDownloadTask? task,
    OfflineTrackEntry? savedEntry,
    bool downloaded,
  ) {
    if (downloaded) return 'Downloaded';
    if (task?.status == ManagedDownloadStatus.waiting) {
      return 'Waiting to download';
    }
    if (task?.status == ManagedDownloadStatus.downloading) return 'Downloading';
    if (task?.status == ManagedDownloadStatus.failed) return 'Download failed';
    if (task?.status == ManagedDownloadStatus.completed) {
      return 'Checking saved file';
    }
    if (savedEntry?.availability == OfflineFileAvailability.missing) {
      return 'Downloaded file is missing';
    }
    if (savedEntry?.availability == OfflineFileAvailability.sizeMismatch) {
      return 'Downloaded file needs repair';
    }
    return null;
  }

  Future<void> _cancelDownload(DownloadManager manager, String taskId) async {
    final job = _activeDownloads[taskId];
    if (job != null) {
      await job.cancel();
    } else {
      await manager.cancel(taskId);
    }
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
    required this.downloadStatus,
    required this.downloadProgress,
    required this.onDownloadAction,
    required this.downloadActionLabel,
    required this.onCancelDownload,
    required this.onOpenDownloads,
    required this.onDownloadUnavailable,
  });

  final MusicTrack track;
  final String credit;
  final VoidCallback onPlay;
  final VoidCallback? onOpen;
  final VoidCallback? onOpenLicense;
  final VoidCallback onAddToQueue;
  final VoidCallback onPlayNext;
  final String? downloadStatus;
  final double? downloadProgress;
  final VoidCallback? onDownloadAction;
  final String downloadActionLabel;
  final VoidCallback? onCancelDownload;
  final VoidCallback? onOpenDownloads;
  final VoidCallback? onDownloadUnavailable;

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
                      if (downloadStatus != null) ...[
                        const SizedBox(height: ThemeConstants.spacing4),
                        Text(
                          downloadStatus!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color:
                                downloadStatus == 'Download failed' ||
                                    downloadStatus == 'Not available offline' ||
                                    downloadStatus ==
                                        'Downloaded file needs repair' ||
                                    downloadStatus ==
                                        'Downloaded file is missing'
                                ? scheme.error
                                : scheme.primary,
                          ),
                        ),
                        if (downloadProgress != null) ...[
                          const SizedBox(height: ThemeConstants.spacing4),
                          LinearProgressIndicator(value: downloadProgress),
                        ],
                      ],
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
                        onDownloadAction?.call();
                      case 'cancelDownload':
                        onCancelDownload?.call();
                      case 'openDownloads':
                        onOpenDownloads?.call();
                      case 'downloadUnavailable':
                        onDownloadUnavailable?.call();
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
                    if (onDownloadAction != null)
                      PopupMenuItem(
                        value: 'download',
                        child: Text(downloadActionLabel),
                      ),
                    if (onCancelDownload != null)
                      const PopupMenuItem(
                        value: 'cancelDownload',
                        child: Text('Cancel download'),
                      ),
                    if (onOpenDownloads != null)
                      const PopupMenuItem(
                        value: 'openDownloads',
                        child: Text('Open in Downloads'),
                      ),
                    if (onDownloadUnavailable != null)
                      const PopupMenuItem(
                        value: 'downloadUnavailable',
                        child: Text('Why can’t I save offline?'),
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

class _SearchFooter extends StatelessWidget {
  const _SearchFooter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(ThemeConstants.spacing16),
    child: Center(child: child),
  );
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice();

  @override
  Widget build(BuildContext context) {
    return const _MessageState(
      icon: Icons.cloud_off_rounded,
      title: 'Online music is unavailable',
      message: 'No online music source is available in this build.',
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
