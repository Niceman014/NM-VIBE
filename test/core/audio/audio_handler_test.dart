import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:nm_vibe/core/audio/audio_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NmVibeAudioHandler state publishing', () {
    late _FakeAudioPlayer player;
    late NmVibeAudioHandler handler;

    setUp(() {
      player = _FakeAudioPlayer();
      handler = NmVibeAudioHandler.forTesting(player);
    });

    tearDown(() async {
      await handler.dispose();
    });

    test('rapid repeat and shuffle changes publish without stream errors', () async {
      final playbackStates = <PlaybackState>[];
      final subscription = handler.playbackState.listen(playbackStates.add);
      final changes = <Future<void>>[];
      for (var index = 0; index < 24; index++) {
        changes.add(
          handler.setRepeatMode(
            AudioServiceRepeatMode.values[index % 3],
          ),
        );
        changes.add(
          handler.setShuffleMode(
            index.isEven
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
          ),
        );
      }

      await Future.wait(changes);
      await subscription.cancel();

      expect(playbackStates, isNotEmpty);
      expect(
        handler.playbackState.value.repeatMode,
        AudioServiceRepeatMode.all,
      );
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
    });

    test('playback events and mode changes can publish concurrently', () async {
      await handler.setQueue([_item('one'), _item('two')], autoPlay: true);
      final changes = <Future<void>>[];
      for (var index = 0; index < 20; index++) {
        changes.add(
          handler.setRepeatMode(
            index.isEven
                ? AudioServiceRepeatMode.all
                : AudioServiceRepeatMode.one,
          ),
        );
        changes.add(
          handler.setShuffleMode(
            index.isEven
                ? AudioServiceShuffleMode.all
                : AudioServiceShuffleMode.none,
          ),
        );
        player.emitPlaybackEvent(index.isEven ? 0 : 1);
      }

      await Future.wait(changes);

      expect(handler.isPlaying, isTrue);
      expect(handler.currentQueue.map((item) => item.id), ['one', 'two']);
      expect(handler.playbackState.value.repeatMode, AudioServiceRepeatMode.one);
      expect(
        handler.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
    });

    test('queue changes during playback keep the published queue consistent', () async {
      await handler.setQueue(
        [_item('one'), _item('two'), _item('three')],
      );
      await handler.addNext([_item('next')]);
      await handler.addToQueueEnd([_item('last')]);
      await handler.moveQueueItem(3, 1);
      await handler.removeQueueItemAt(2);

      expect(
        handler.currentQueue.map((item) => item.id),
        ['one', 'three', 'two', 'last'],
      );
      expect(handler.isPlaying, isTrue);
    });

    test('disposing closes published streams and is safe to repeat', () async {
      final closed = Completer<void>();
      final subscription = handler.playbackState.listen(
        null,
        onDone: closed.complete,
      );

      await handler.dispose();
      await closed.future;
      await subscription.cancel();
      await handler.dispose();

      expect(handler.playbackState.isClosed, isTrue);
      expect(handler.queue.isClosed, isTrue);
      expect(handler.mediaItem.isClosed, isTrue);
      expect(player.isDisposed, isTrue);
    });
  });
}

MediaItem _item(String id) => MediaItem(
  id: id,
  title: id,
  extras: {'path': 'C:/music/$id.mp3'},
);

class _FakeAudioPlayer extends AudioPlayer {
  final StreamController<PlaybackEvent> _events =
      StreamController<PlaybackEvent>.broadcast(sync: true);
  final StreamController<int?> _indices = StreamController<int?>.broadcast(
    sync: true,
  );
  final StreamController<PlayerException> _errors =
      StreamController<PlayerException>.broadcast(sync: true);

  bool _playing = false;
  bool _streamsClosed = false;
  bool isDisposed = false;
  int? _currentIndex;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _events.stream;

  @override
  Stream<int?> get currentIndexStream => _indices.stream;

  @override
  Stream<PlayerException> get errorStream => _errors.stream;

  @override
  bool get playing => _playing;

  @override
  ProcessingState get processingState =>
      _playing ? ProcessingState.ready : ProcessingState.idle;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  double get speed => 1;

  @override
  int? get currentIndex => _currentIndex;

  void emitPlaybackEvent(int? index) {
    _currentIndex = index;
    _events.add(PlaybackEvent(
      currentIndex: index,
      processingState: processingState,
    ));
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    await Future<void>.delayed(const Duration(microseconds: 10));
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    await Future<void>.delayed(const Duration(microseconds: 10));
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    _currentIndex = initialIndex ?? 0;
    _indices.add(_currentIndex);
    emitPlaybackEvent(_currentIndex);
    return Duration.zero;
  }

  @override
  Future<void> addAudioSources(List<AudioSource> audioSources) async {}

  @override
  Future<void> insertAudioSource(int index, AudioSource audioSource) async {}

  @override
  Future<void> removeAudioSourceAt(int index) async {}

  @override
  Future<void> moveAudioSource(int currentIndex, int newIndex) async {}

  @override
  Future<void> play() async {
    _playing = true;
    emitPlaybackEvent(_currentIndex);
  }

  @override
  Future<void> stop() async {
    _playing = false;
    if (!_streamsClosed) emitPlaybackEvent(_currentIndex);
  }

  @override
  Future<void> dispose() async {
    _streamsClosed = true;
    await _events.close();
    await _indices.close();
    await _errors.close();
    await super.dispose();
    isDisposed = true;
  }
}
