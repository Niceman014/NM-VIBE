import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/features/player/controllers/player_controller.dart';
import 'package:nm_vibe/features/player/widgets/playback_error_banner.dart';

void main() {
  test('player recovery actions depend on queue state', () {
    final failedTrack = SongFixture.track;
    final nextTrack = SongFixture.nextTrack;
    final failedState = PlayerState(
      queue: [failedTrack, nextTrack],
      currentIndex: 0,
      error: 'Playback failed.',
    );
    final terminalState = PlayerState(
      queue: [failedTrack],
      currentIndex: 0,
      error: 'Playback failed.',
    );

    expect(failedState.canRetry, isTrue);
    expect(failedState.canSkip, isTrue);
    expect(terminalState.canRetry, isTrue);
    expect(terminalState.canSkip, isFalse);
    expect(failedState.copyWith(loading: true).canRetry, isFalse);
  });

  testWidgets('offers Retry and Skip when another queue item exists', (
    tester,
  ) async {
    var retried = false;
    var skipped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackErrorBanner(
            error: 'Could not play this track.',
            onRetry: () => retried = true,
            onSkip: () => skipped = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.tap(find.text('Skip'));

    expect(retried, isTrue);
    expect(skipped, isTrue);
    expect(find.text('No next track is available.'), findsNothing);
  });

  testWidgets('shows no-next guidance and hides Skip at the end of queue', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackErrorBanner(
            error: 'Could not play this track.',
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Skip'), findsNothing);
    expect(find.text('No next track is available.'), findsOneWidget);
  });
}

class SongFixture {
  static final track = Song(
    id: 'local:one',
    filePath: '/music/one.mp3',
    title: 'One',
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    duration: Duration(minutes: 1),
    fileSize: 10,
    addedAt: DateTime.utc(2026),
  );

  static final nextTrack = Song(
    id: 'local:two',
    filePath: '/music/two.mp3',
    title: 'Two',
    artist: 'Artist',
    album: 'Album',
    albumArtist: 'Artist',
    duration: Duration(minutes: 1),
    fileSize: 10,
    addedAt: DateTime.utc(2026),
  );
}
