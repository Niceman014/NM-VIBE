import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/features/library/views/library_page.dart';
import 'package:nm_vibe/features/library/controllers/scan_controller.dart';
import 'package:nm_vibe/features/discover/views/discover_page.dart';
import 'package:nm_vibe/features/playlists/views/playlists_page.dart';
import 'package:nm_vibe/features/settings/views/settings_page.dart';
import 'desktop_now_playing_pane.dart';
import 'mini_player.dart';

/// Root navigation shell: compact bottom navigation on phones, a navigation
/// rail on tablets/desktop, with the mini player pinned above the navigation.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !ref.read(settingsControllerProvider).autoScanOnStartup) {
        return;
      }
      ref.read(scanControllerProvider.notifier).scanLibrary();
    });
  }

  static const List<Widget> _pages = [
    LibraryPage(),
    DiscoverPage(),
    PlaylistsPage(),
    SettingsPage(),
  ];

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music),
      label: 'Library',
    ),
    NavigationDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore_rounded),
      label: 'Discover',
    ),
    NavigationDestination(
      icon: Icon(Icons.queue_music_outlined),
      selectedIcon: Icon(Icons.queue_music),
      label: 'Playlists',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  static const List<NavigationRailDestination> _railDestinations = [
    NavigationRailDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music),
      label: Text('Library'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore_rounded),
      label: Text('Discover'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.queue_music_outlined),
      selectedIcon: Icon(Icons.queue_music),
      label: Text('Playlists'),
    ),
    NavigationRailDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: Text('Settings'),
    ),
  ];

  void _onDestinationSelected(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final hasDesktopPlayer = MediaQuery.sizeOf(context).width >= 1180;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (isWide) ...[
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: _onDestinationSelected,
                destinations: _railDestinations,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ThemeConstants.spacing16,
                  ),
                  child: _BrandMark(),
                ),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: IndexedStack(index: _index, children: _pages),
                        ),
                        if (!hasDesktopPlayer) const MiniPlayer(),
                      ],
                    ),
                  ),
                  if (hasDesktopPlayer) ...[
                    const VerticalDivider(width: 1),
                    const SizedBox(
                      width: ThemeConstants.desktopPlayerPaneWidth,
                      child: DesktopNowPlayingPane(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _onDestinationSelected,
              destinations: _destinations,
            ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Text(
        'NM',
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w900),
      ),
    );
  }
}
