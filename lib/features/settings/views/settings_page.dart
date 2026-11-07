import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:nm_vibe/core/constants/app_constants.dart';
import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/scanner/artwork_service.dart';
import 'package:nm_vibe/shared/providers/music_providers.dart';
import 'package:nm_vibe/core/storage/settings_service.dart';

import '../../../features/updates/controllers/update_controller.dart';
import '../../../features/updates/services/update_strategy.dart';

import 'package:nm_vibe/core/utils/formatters.dart';
import 'package:nm_vibe/core/platform/platform_info.dart';
import 'package:nm_vibe/shared/widgets/album_art.dart';

import '../../library/controllers/scan_controller.dart';

import 'package:nm_vibe/data/models/song_model.dart';

import '../../player/controllers/player_controller.dart';
import '../controllers/equalizer_controller.dart';

part 'settings_page_sections.dart';
part 'settings_page_widgets.dart';

/// Everything the user can tune: appearance, library scanning, playback
/// (including the Android equalizer) and about/updates.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _version = AppConstants.appVersion;
  bool _loadingVersion = true;
  bool _clearingLibrary = false;
  int _artworkBytes = 0;
  int _downloadBytes = 0;

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _loadArtworkSize();
    _loadDownloadSize();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _loadingVersion = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingVersion = false);
    }
  }

  Future<void> _loadArtworkSize() async {
    try {
      final bytes = await ref.read(artworkServiceProvider).sizeBytes();
      if (!mounted) return;
      setState(() => _artworkBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _artworkBytes = 0);
    }
  }

  Future<void> _loadDownloadSize() async {
    try {
      final bytes = await ref
          .read(internetArchiveServiceProvider)
          .downloadedBytes();
      if (mounted) setState(() => _downloadBytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _downloadBytes = 0);
    }
  }

  Future<void> _deleteDownloads() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete offline downloads?'),
        content: const Text(
          'This permanently removes all Internet Archive downloads from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete downloads'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(downloadManagerProvider).cancelAll();
      await ref.read(internetArchiveServiceProvider).deleteDownloads();
      final songs = ref.read(songsProvider).value ?? const <Song>[];
      final repository = ref.read(libraryRepositoryProvider);
      for (final song in songs.where(
        (song) => song.isDownloaded && song.source == 'internet_archive',
      )) {
        await repository.updateSong(
          song.copyWith(
            filePath: song.streamUrl ?? song.filePath,
            fileSize: 0,
            isDownloaded: false,
          ),
        );
      }
      ref.invalidate(offlineIndexProvider);
      await _loadDownloadSize();
      _showSnack('Offline downloads deleted');
    } catch (error) {
      _showSnack('Could not delete downloads: $error');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------------------------------------------- library actions
  Future<void> _runScan() async {
    try {
      await ref.read(scanControllerProvider.notifier).scanLibrary();
      await _loadArtworkSize();
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

  Future<void> _removeFolder(String folder) async {
    final current = ref.read(settingsControllerProvider);
    final updated = current.libraryFolders
        .where((item) => item != folder)
        .toList(growable: false);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setLibraryFolders(updated);
      _showSnack('Folder removed — scan again to refresh your library');
    } catch (error) {
      _showSnack('Could not update folders: $error');
    }
  }

  Future<void> _clearLibrary() async {
    final songs = ref.read(songsProvider).value ?? const <Song>[];
    final playlists = ref.read(playlistsProvider).value?.length ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear library?'),
        content: Text(
          'This removes ${songs.length} ${songs.length == 1 ? 'song' : 'songs'} '
          'and $playlists ${playlists == 1 ? 'playlist' : 'playlists'} from '
          'NM VIBE. Your audio files stay exactly where they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear library'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingLibrary = true);
    try {
      await ref.read(scanControllerProvider.notifier).clearLibrary();
      await _loadArtworkSize();
      _showSnack('Library cleared');
    } catch (error) {
      _showSnack('Could not clear the library: $error');
    } finally {
      if (mounted) setState(() => _clearingLibrary = false);
    }
  }

  Future<void> _checkForUpdates() async {
    await ref.read(updateControllerProvider.notifier).checkForUpdates();
  }

  Future<void> _installUpdate() =>
      ref.read(updateControllerProvider.notifier).installAvailable();

  Future<void> _cancelUpdateDownload() =>
      ref.read(updateControllerProvider.notifier).cancelDownload();

  // ------------------------------------------------------------- sheet actions
  Future<void> _showSpeedSheet() async {
    final current = ref.read(playerControllerProvider).speed;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing24,
                  ThemeConstants.spacing4,
                  ThemeConstants.spacing8,
                  ThemeConstants.spacing4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Playback speed',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              for (final speed in const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                ListTile(
                  leading: const Icon(Icons.speed_rounded),
                  title: Text(formatPlaybackSpeed(speed)),
                  trailing: speed == current
                      ? Icon(
                          Icons.check_rounded,
                          color: theme.colorScheme.primary,
                        )
                      : null,
                  selected: speed == current,
                  onTap: () {
                    ref.read(playerControllerProvider.notifier).setSpeed(speed);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: ThemeConstants.spacing8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSleepTimerSheet() async {
    final player = ref.read(playerControllerProvider);
    final remaining = player.sleepTimerRemaining;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  ThemeConstants.spacing24,
                  ThemeConstants.spacing4,
                  ThemeConstants.spacing8,
                  ThemeConstants.spacing4,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sleep timer',
                            style: theme.textTheme.titleLarge,
                          ),
                          if (remaining != null)
                            Text(
                              'Stops in ${formatDuration(remaining)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              for (final minutes in const [5, 10, 15, 30, 45, 60])
                ListTile(
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text('$minutes minutes'),
                  onTap: () {
                    ref
                        .read(playerControllerProvider.notifier)
                        .setSleepTimer(Duration(minutes: minutes));
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Turn off'),
                enabled: remaining != null,
                onTap: () {
                  ref
                      .read(playerControllerProvider.notifier)
                      .setSleepTimer(null);
                  Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: ThemeConstants.spacing8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEqualizerSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.92,
        child: _EqualizerSheet(),
      ),
    );
  }

  // -------------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;
    final sidePadding = width >= 1000
        ? ((width - 960) / 2).clamp(24.0, 480.0)
        : (width >= 600 ? 24.0 : 16.0);

    final settings = ref.watch(settingsControllerProvider);
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final player = ref.watch(playerControllerProvider);
    final updateState = ref.watch(updateControllerProvider);
    final scanState = ref.watch(scanControllerProvider);
    final songs = ref.watch(songsProvider).value ?? const <Song>[];
    final lastScan =
        scanState.lastScan ?? ref.watch(lastScanTimeProvider).value;

    final appearance = _appearanceSection(
      context,
      settings: settings,
      controller: settingsController,
    );
    final library = _librarySection(
      context,
      settings: settings,
      controller: settingsController,
      scanState: scanState,
      songs: songs,
      lastScan: lastScan,
    );
    final playback = _playbackSection(context, player: player);
    final about = _aboutSection(context, state: updateState);
    final downloads = _downloadsSection(
      context,
      settings: settings,
      controller: settingsController,
      usedBytes: _downloadBytes,
      onDelete: _deleteDownloads,
    );

    final content = isWide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(children: [appearance, library])),
              const SizedBox(width: ThemeConstants.spacing24),
              Expanded(child: Column(children: [playback, downloads, about])),
            ],
          )
        : Column(children: [appearance, library, playback, downloads, about]);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                sidePadding,
                ThemeConstants.spacing8,
                sidePadding,
                ThemeConstants.spacing16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appName.toUpperCase(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 2.6,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: ThemeConstants.spacing8),
                  Text(
                    'Settings',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: ThemeConstants.spacing8),
                  Text(
                    'Shape how NM VIBE looks, scans and plays.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: sidePadding),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: content,
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: ThemeConstants.spacing32),
          ),
        ],
      ),
    );
  }
}
