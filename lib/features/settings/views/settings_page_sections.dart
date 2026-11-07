part of 'settings_page.dart';

extension _SettingsPageSections on _SettingsPageState {
  Widget _downloadsSection(
    BuildContext context, {
    required AppSettings settings,
    required SettingsController controller,
    required int usedBytes,
    required VoidCallback onDelete,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(ThemeConstants.radiusLarge),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          Icons.download_for_offline_outlined,
          color: theme.colorScheme.primary,
        ),
        title: const Text('Offline downloads'),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.wifi_rounded),
            title: const Text('Wi-Fi only downloads', softWrap: true),
            subtitle: const Text('Pause on mobile data'),
            value: settings.wifiOnlyDownloads,
            onChanged: controller.setWifiOnlyDownloads,
          ),
          ListTile(
            leading: const Icon(Icons.storage_rounded),
            title: const Text('Storage limit'),
            subtitle: Text('${_formatDownloadSize(usedBytes)} used'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DropdownButtonFormField<int>(
              initialValue: settings.downloadStorageLimitMb,
              isExpanded: true,
              items: const [512, 1024, 2048, 5120]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(
                        value >= 1024 ? '${value ~/ 1024} GB' : '$value MB',
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) controller.setDownloadStorageLimitMb(value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: usedBytes > 0 ? onDelete : null,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete downloads'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDownloadSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  // -------------------------------------------------------------- appearance
  Widget _appearanceSection(
    BuildContext context, {
    required AppSettings settings,
    required SettingsController controller,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return _SettingsSection(
      title: 'Appearance',
      icon: Icons.palette_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
            ThemeConstants.spacing12,
          ),
          child: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('Auto'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) =>
                controller.setThemeMode(selection.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing16,
            0,
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Accent colour', style: theme.textTheme.titleSmall),
              const SizedBox(height: ThemeConstants.spacing12),
              Wrap(
                spacing: ThemeConstants.spacing8,
                runSpacing: ThemeConstants.spacing8,
                children: [
                  for (
                    var index = 0;
                    index < ThemeConstants.accentValues.length;
                    index++
                  )
                    _AccentDot(
                      color: Color(ThemeConstants.accentValues[index]),
                      name: ThemeConstants.accentNames[index],
                      selected:
                          settings.seedColorValue ==
                          ThemeConstants.accentValues[index],
                      onTap: () => controller.setSeedColorValue(
                        ThemeConstants.accentValues[index],
                      ),
                    ),
                ],
              ),
              if (PlatformInfo.isAndroid && settings.useDynamicColor) ...[
                const SizedBox(height: ThemeConstants.spacing12),
                Text(
                  'Wallpaper colours override the accent while dynamic colour is on.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_rounded),
          title: const Text('Pure black dark theme'),
          subtitle: const Text('Use black surfaces when dark mode is active'),
          value: settings.usePureBlackTheme,
          onChanged: controller.setUsePureBlackTheme,
        ),
        if (PlatformInfo.isAndroid)
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined),
            title: const Text('Dynamic colour'),
            subtitle: const Text('Match your wallpaper palette (Android 12+)'),
            value: settings.useDynamicColor,
            onChanged: controller.setUseDynamicColor,
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- library
  Widget _librarySection(
    BuildContext context, {
    required AppSettings settings,
    required SettingsController controller,
    required ScanState scanState,
    required List<Song> songs,
    required DateTime? lastScan,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final libraryBytes =
        songs.fold<int>(0, (total, song) => total + song.fileSize) +
        _artworkBytes;
    final progressLabel = scanState.total > 0
        ? '${scanState.processed} of ${scanState.total} files'
        : 'Looking for audio files…';

    return _SettingsSection(
      title: 'Library',
      icon: Icons.library_music_outlined,
      children: [
        ListTile(
          leading: const Icon(Icons.refresh_rounded),
          title: const Text('Scan now'),
          subtitle: Text(
            scanState.scanning
                ? progressLabel
                : scanState.error != null
                ? scanState.error!
                : 'Look for new and changed music',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: scanState.scanning
              ? const SizedBox(
                  width: ThemeConstants.spacing24,
                  height: ThemeConstants.spacing24,
                  child: CircularProgressIndicator(
                    strokeWidth: ThemeConstants.spacing4,
                  ),
                )
              : const Icon(Icons.chevron_right_rounded),
          enabled: !scanState.scanning,
          onTap: scanState.scanning ? null : _runScan,
        ),
        if (scanState.scanning)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeConstants.spacing16,
              0,
              ThemeConstants.spacing16,
              ThemeConstants.spacing12,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: scanState.total > 0 ? scanState.progress : null,
              ),
            ),
          ),
        if (scanState.scanning && (scanState.currentFile ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ThemeConstants.spacing16,
              0,
              ThemeConstants.spacing16,
              ThemeConstants.spacing12,
            ),
            child: Text(
              scanState.currentFile!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (PlatformInfo.usesMediaStoreScanner)
          const ListTile(
            leading: Icon(Icons.phone_android_rounded),
            title: Text('Device media'),
            subtitle: Text(
              'Android MediaStore · audio permission is requested when scanning',
            ),
          )
        else ...[
          if (settings.libraryFolders.isEmpty)
            const ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text('Music folders'),
              subtitle: Text('Default Music folder'),
            )
          else
            for (final folder in settings.libraryFolders)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(
                  folder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: const Text('Scanned folder'),
                trailing: IconButton(
                  tooltip: 'Remove folder',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: scanState.scanning
                      ? null
                      : () => _removeFolder(folder),
                ),
              ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: const Text('Add music folder'),
            subtitle: const Text('Pick a folder to include in your library'),
            trailing: const Icon(Icons.chevron_right_rounded),
            enabled: !scanState.scanning,
            onTap: scanState.scanning ? null : _addFolder,
          ),
        ],
        SwitchListTile(
          secondary: const Icon(Icons.autorenew_rounded),
          title: const Text('Scan on launch'),
          subtitle: const Text('Pick up new files automatically'),
          value: settings.autoScanOnStartup,
          onChanged: controller.setAutoScanOnStartup,
        ),
        ListTile(
          leading: const Icon(Icons.history_rounded),
          title: const Text('Last scan'),
          subtitle: Text(
            lastScan == null ? 'Never scanned' : formatRelativeDate(lastScan),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.data_usage_rounded),
          title: const Text('Storage used'),
          subtitle: Text(
            '${formatFileSize(libraryBytes)} · ${trackCountLabel(songs.length)} · '
            'artwork ${formatFileSize(_artworkBytes)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
          title: Text(
            'Clear library',
            style: theme.textTheme.bodyLarge?.copyWith(color: scheme.error),
          ),
          subtitle: const Text('Remove songs and playlists from NM VIBE only'),
          trailing: _clearingLibrary
              ? const SizedBox(
                  width: ThemeConstants.spacing24,
                  height: ThemeConstants.spacing24,
                  child: CircularProgressIndicator(
                    strokeWidth: ThemeConstants.spacing4,
                  ),
                )
              : null,
          enabled: !_clearingLibrary,
          onTap: _clearingLibrary ? null : _clearLibrary,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- playback
  Widget _playbackSection(BuildContext context, {required PlayerState player}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = player.current;
    final sleepRemaining = player.sleepTimerRemaining;

    return _SettingsSection(
      title: 'Playback',
      icon: Icons.play_circle_outline_rounded,
      children: [
        if (current == null)
          const ListTile(
            leading: Icon(Icons.music_off_rounded),
            title: Text('Nothing playing'),
            subtitle: Text('Pick a song from your library to see it here'),
          )
        else
          ListTile(
            leading: AlbumArt(
              artworkKey: current.artworkKey,
              size: 48,
              borderRadius: 12,
              isPlaying: player.playing,
            ),
            title: Text(
              current.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${player.playing ? 'Playing' : 'Paused'} · ${current.displayArtist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: player.playing ? 'Pause' : 'Resume',
              icon: Icon(
                player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              onPressed: () =>
                  ref.read(playerControllerProvider.notifier).togglePlayPause(),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.speed_rounded),
          title: const Text('Playback speed'),
          subtitle: const Text('Slow down or speed up your music'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatPlaybackSpeed(player.speed),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: ThemeConstants.spacing8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          onTap: _showSpeedSheet,
        ),
        ListTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: const Text('Sleep timer'),
          subtitle: Text(
            sleepRemaining == null
                ? 'Stop playback after a set time'
                : 'Stops in ${formatDuration(sleepRemaining)}',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _showSleepTimerSheet,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lyrics_outlined),
          title: const Text('Show lyrics in player'),
          subtitle: const Text('Display synced lyrics when available'),
          value: ref.watch(settingsControllerProvider).showLyricsInPlayer,
          onChanged: ref
              .read(settingsControllerProvider.notifier)
              .setShowLyricsInPlayer,
        ),
        if (PlatformInfo.supportsEqualizer)
          ListTile(
            leading: const Icon(Icons.equalizer_rounded),
            title: const Text('Equalizer'),
            subtitle: const Text('Presets, bass boost and fine band control'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _showEqualizerSheet,
          ),
      ],
    );
  }

  // ------------------------------------------------------------------- about
  Widget _aboutSection(BuildContext context, {required UpdateUiState state}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy =
        state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.verifying;
    final canInstall =
        state.status == UpdateStatus.available &&
        (state.manifest == null || state.manifest!.downloadConfigured);
    return _SettingsSection(
      title: 'About',
      icon: Icons.info_outline_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary, scheme.tertiary],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  'NM',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: ThemeConstants.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: ThemeConstants.spacing4),
                    Text(
                      _loadingVersion
                          ? 'Version ${AppConstants.appVersion}'
                          : 'Version $_version',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: ThemeConstants.spacing4),
                    Text(
                      AppConstants.appTagline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.system_update_alt_rounded),
          title: const Text('Check for updates'),
          subtitle: Text(_updateStateDescription(state)),
          trailing: busy
              ? const SizedBox(
                  width: ThemeConstants.spacing24,
                  height: ThemeConstants.spacing24,
                  child: CircularProgressIndicator(
                    strokeWidth: ThemeConstants.spacing4,
                  ),
                )
              : const Icon(Icons.chevron_right_rounded),
          enabled: !busy,
          onTap: busy ? null : _checkForUpdates,
        ),
        if (state.status == UpdateStatus.available) ...[
          if ((state.manifest?.releaseNotes ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(state.manifest!.releaseNotes),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canInstall ? _installUpdate : null,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  canInstall
                      ? 'Update to v${state.manifest?.version ?? 'latest'}'
                      : 'Installer hosting is not configured yet',
                ),
              ),
            ),
          ),
        ],
        if (state.status == UpdateStatus.downloading) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: LinearProgressIndicator(value: state.progress),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.progress == null
                        ? 'Downloading update…'
                        : 'Downloading ${(state.progress! * 100).round()}%',
                  ),
                ),
                TextButton.icon(
                  onPressed: _cancelUpdateDownload,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ],
        if (state.status == UpdateStatus.verifying)
          const ListTile(
            leading: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            title: Text('Verifying installer…'),
          ),
        if (state.status == UpdateStatus.failed ||
            state.status == UpdateStatus.cancelled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    state.message ?? 'Update failed. Please try again.',
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                TextButton.icon(
                  onPressed: _checkForUpdates,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        if (state.status == UpdateStatus.launched ||
            state.status == UpdateStatus.openedPage ||
            state.status == UpdateStatus.upToDate)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              state.message ?? _updateStateDescription(state),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licences'),
          subtitle: const Text('The packages that power NM VIBE'),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => showLicensePage(
            context: context,
            applicationName: AppConstants.appName,
            applicationVersion: _version,
            applicationLegalese:
                'Free and open-source software. Third-party licenses apply.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
            ThemeConstants.spacing16,
            ThemeConstants.spacing24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Commercial release planned · Local playback without sign-in',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ThemeConstants.spacing4),
              Text(
                '© ${DateTime.now().year} NM VIBE',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _updateStateDescription(UpdateUiState state) => switch (state.status) {
    UpdateStatus.idle =>
      _loadingVersion
          ? 'Current version'
          : 'You are on v$_version. Tap to check.',
    UpdateStatus.checking => 'Checking for updates…',
    UpdateStatus.upToDate => 'You are up to date.',
    UpdateStatus.available =>
      'Version ${state.manifest?.version ?? 'available'} is ready.',
    UpdateStatus.downloading => 'Downloading update…',
    UpdateStatus.verifying => 'Verifying installer…',
    UpdateStatus.failed => state.message ?? 'Update check failed.',
    UpdateStatus.cancelled => 'Update cancelled.',
    UpdateStatus.openedPage => state.message ?? 'Opened the update page.',
    UpdateStatus.launched => state.message ?? 'Installer started.',
  };
}
