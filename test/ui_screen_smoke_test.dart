import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nm_vibe/core/constants/theme_constants.dart';
import 'package:nm_vibe/data/repositories/in_memory_library_repository.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/scanner/artwork_service.dart';
import 'package:nm_vibe/core/audio/audio_handler.dart';
import 'package:nm_vibe/core/storage/settings_service.dart';
import 'package:nm_vibe/core/theme/app_theme.dart';
import 'package:nm_vibe/features/discover/views/discover_page.dart';
import 'package:nm_vibe/features/library/views/library_page.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/shared/widgets/loading_skeleton.dart';
import 'package:nm_vibe/shared/widgets/song_tile.dart';
import 'package:nm_vibe/features/player/views/now_playing_page.dart';
import 'package:nm_vibe/features/playlists/views/playlists_page.dart';
import 'package:nm_vibe/features/settings/views/settings_page.dart';
import 'package:nm_vibe/shared/widgets/app_shell.dart';
import 'package:nm_vibe/shared/widgets/desktop_now_playing_pane.dart';

void main() {
  late AppPreferences preferences;
  late InMemoryLibraryRepository repository;
  late NmVibeAudioHandler audioHandler;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'nm_vibe.autoScan': false});
    preferences = await AppPreferences.open();
    repository = InMemoryLibraryRepository();
    audioHandler = NmVibeAudioHandler();
  });

  tearDownAll(() async {
    await audioHandler.player.dispose();
    await repository.close();
  });

  Widget app(
    Widget page, {
    double textScale = 1,
    InMemoryLibraryRepository? library,
  }) {
    return ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(library ?? repository),
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(preferences),
        ),
        audioHandlerProvider.overrideWithValue(audioHandler),
        artworkServiceProvider.overrideWithValue(ArtworkService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(ThemeConstants.defaultSeed),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: page,
          ),
        ),
      ),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget page, {
    double textScale = 1,
    double width = 390,
    double height = 844,
    InMemoryLibraryRepository? library,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(app(page, textScale: textScale, library: library));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Screen overflow at width $width and text scale $textScale',
    );
  }

  testWidgets('library screen renders its empty state', (tester) async {
    await pumpScreen(tester, const LibraryPage());
    expect(find.text('Your vibe starts here'), findsOneWidget);
    expect(find.text('Scan my music'), findsOneWidget);
  });

  testWidgets('library header fits narrow widths and large text', (tester) async {
    for (final width in [254.0, 360.0, 600.0]) {
      for (final textScale in [1.0, 2.0]) {
        await pumpScreen(
          tester,
          const LibraryPage(),
          width: width,
          height: 2000,
          textScale: textScale,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Overflow at width $width and text scale $textScale',
        );
      }
    }
  });

  testWidgets('library shows a skeleton while its first snapshot loads', (
    tester,
  ) async {
    final delayedRepository = _DelayedLibraryRepository();
    await pumpScreen(tester, const LibraryPage(), library: delayedRepository);
    expect(find.byType(SkeletonSongList), findsOneWidget);
  });

  testWidgets('library shows a retry action when its stream fails', (
    tester,
  ) async {
    final failedRepository = _FailedLibraryRepository();
    await pumpScreen(tester, const LibraryPage(), library: failedRepository);
    expect(find.text('Could not load your library'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('5,000-song library builds visible rows lazily', (tester) async {
    final largeRepository = InMemoryLibraryRepository(
      songs: List<Song>.generate(
        5000,
        (index) => Song(
          id: 'local:$index',
          filePath: 'C:/Music/track_$index.mp3',
          title: 'Track ${index.toString().padLeft(5, '0')}',
          artist: 'Artist ${index % 100}',
          album: 'Album ${index % 250}',
          albumArtist: 'Artist ${index % 100}',
          duration: const Duration(minutes: 3),
          fileSize: 1024,
          addedAt: DateTime.utc(2026).add(Duration(seconds: index)),
        ),
      ),
    );
    addTearDown(largeRepository.close);
    await pumpScreen(tester, const LibraryPage(), library: largeRepository);

    expect(
      tester.widgetList<SongTile>(find.byType(SongTile)).length,
      lessThanOrEqualTo(30),
    );
    expect(find.text('Track 00000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('discover screen renders its configured or setup state', (
    tester,
  ) async {
    await pumpScreen(tester, const DiscoverPage());
    expect(find.text('Find your next favourite'), findsOneWidget);
  });

  testWidgets('playlists screen renders its empty state', (tester) async {
    await pumpScreen(tester, const PlaylistsPage());
    expect(find.text('No playlists yet'), findsOneWidget);
    expect(find.text('Create playlist'), findsOneWidget);
  });

  testWidgets('settings screen renders at large text scale', (tester) async {
    await pumpScreen(tester, const SettingsPage(), textScale: 1.8);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline download controls open without narrow-screen overflow', (
    tester,
  ) async {
    await pumpScreen(tester, const SettingsPage(), textScale: 1.8);
    final settingsScrollable = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(settingsScrollable).position;
    position.jumpTo(
      (position.maxScrollExtent - 500).clamp(0.0, position.maxScrollExtent),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Wi-Fi only downloads'), findsOneWidget);
    expect(find.text('Storage limit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('now playing screen has a clear empty state', (tester) async {
    await pumpScreen(tester, const NowPlayingPage());
    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.byTooltip('Close player'), findsOneWidget);
  });

  testWidgets('wide desktop shell provides navigation and a player pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(app(const AppShell()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(DesktopNowPlayingPane), findsOneWidget);
    expect(find.text('Choose a song to start listening'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedLibraryRepository extends InMemoryLibraryRepository {
  @override
  Stream<List<Song>> watchSongs() => Stream<List<Song>>.multi((_) {});
}

class _FailedLibraryRepository extends InMemoryLibraryRepository {
  @override
  Stream<List<Song>> watchSongs() =>
      Stream<List<Song>>.error(StateError('test library failure'));
}
