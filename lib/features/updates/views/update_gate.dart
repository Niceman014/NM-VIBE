import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import '../controllers/update_controller.dart';
import '../services/update_strategy.dart';

class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(updateControllerProvider.notifier)
            .checkForUpdates(automatic: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateControllerProvider);
    if (update.requiresUpdate) {
      return _RequiredUpdateScreen(state: update);
    }
    return widget.child;
  }
}

class _RequiredUpdateScreen extends ConsumerWidget {
  const _RequiredUpdateScreen({required this.state});

  final UpdateUiState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(updateControllerProvider.notifier);
    final manifest = state.manifest;
    final canInstall =
        state.status == UpdateStatus.available &&
        (manifest == null || manifest.downloadConfigured);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.system_update_alt_rounded,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Update required',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This version is no longer supported. Install version '
                      '${manifest?.version ?? 'available'} to continue online.',
                      textAlign: TextAlign.center,
                    ),
                    if ((manifest?.releaseNotes ?? '').isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(manifest!.releaseNotes, textAlign: TextAlign.center),
                    ],
                    if (state.status == UpdateStatus.downloading) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(value: state.progress),
                      Text(
                        state.progress == null
                            ? 'Downloading update…'
                            : 'Downloading ${(state.progress! * 100).round()}%',
                      ),
                      TextButton(
                        onPressed: controller.cancelDownload,
                        child: const Text('Cancel download'),
                      ),
                    ] else if (state.status == UpdateStatus.verifying) ...[
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Verifying installer…'),
                    ] else if (state.status == UpdateStatus.failed &&
                        state.message != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        state.message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (state.status == UpdateStatus.available ||
                        state.status == UpdateStatus.failed ||
                        state.status == UpdateStatus.cancelled) ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: canInstall
                              ? controller.installAvailable
                              : state.status == UpdateStatus.failed ||
                                    state.status == UpdateStatus.cancelled
                              ? () => controller.checkForUpdates()
                              : null,
                          icon: Icon(
                            state.status == UpdateStatus.failed
                                ? Icons.refresh_rounded
                                : Icons.download_rounded,
                          ),
                          label: Text(
                            state.status == UpdateStatus.failed ||
                                    state.status == UpdateStatus.cancelled
                                ? 'Retry update check'
                                : canInstall
                                ? 'Install update'
                                : 'Installer hosting is not configured',
                          ),
                        ),
                      ),
                    ] else if (state.status == UpdateStatus.checking) ...[
                      const CircularProgressIndicator(),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const OfflineMusicScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.library_music_outlined),
                        label: const Text('Play offline music'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Offline music remains available while you update.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OfflineMusicScreen extends ConsumerWidget {
  const OfflineMusicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(songsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Offline music')),
      body: songs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load offline music.')),
        data: (allSongs) {
          final offlineSongs = allSongs
              .where((song) => song.isDownloaded || !song.isOnlineTrack)
              .toList(growable: false);
          if (offlineSongs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No music saved on this device yet.'),
              ),
            );
          }
          return ListView.builder(
            itemCount: offlineSongs.length,
            itemBuilder: (context, index) {
              final song = offlineSongs[index];
              return ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: Text(song.displayTitle),
                subtitle: Text(song.displayArtist),
                onTap: () => ref
                    .read(playerControllerProvider.notifier)
                    .playSongs(offlineSongs, initialIndex: index),
              );
            },
          );
        },
      ),
    );
  }
}
