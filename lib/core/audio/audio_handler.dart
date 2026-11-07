import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:just_audio/just_audio.dart';

import 'package:nm_vibe/core/utils/logger.dart';
import 'package:nm_vibe/core/platform/platform_info.dart';

part 'audio_handler_recovery.dart';

/// One band of the Android equalizer.
class EqualizerBandInfo {
  const EqualizerBandInfo({
    required this.index,
    required this.centerFrequency,
    required this.minGain,
    required this.maxGain,
    required this.gain,
  });

  final int index;
  final double centerFrequency;
  final double minGain;
  final double maxGain;
  final double gain;
}

/// The single audio engine of NM VIBE.
///
/// It is a normal [BaseAudioHandler], so the same object powers playback on
/// desktop (no service) and the Android media notification (wrapped by
/// [AudioService.init]). All queue mutations go through this class.
class NmVibeAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  NmVibeAudioHandler._(this._player, this._equalizer) {
    _playerSubscriptions.addAll([
      _player.playbackEventStream.listen(
        _onPlaybackEvent,
        onError: (Object error, StackTrace stackTrace) {
          _log.e('Playback state stream failed', error, stackTrace);
        },
      ),
      _player.currentIndexStream.listen(
        _onCurrentIndexChanged,
        onError: (Object error, StackTrace stackTrace) {
          _log.e('Current track stream failed', error, stackTrace);
        },
      ),
      _player.errorStream.listen(
        _onPlaybackError,
        onError: (Object error, StackTrace stackTrace) {
          _log.e('Playback error stream failed', error, stackTrace);
        },
      ),
    ]);
  }

  @visibleForTesting
  NmVibeAudioHandler.forTesting(AudioPlayer player) : this._(player, null);

  factory NmVibeAudioHandler() {
    if (PlatformInfo.supportsEqualizer) {
      final equalizer = AndroidEqualizer();
      return NmVibeAudioHandler._(
        AudioPlayer(
          audioPipeline: AudioPipeline(androidAudioEffects: [equalizer]),
        ),
        equalizer,
      );
    }
    return NmVibeAudioHandler._(AudioPlayer(), null);
  }

  static const AppLogger _log = AppLogger('AudioHandler');

  final AudioPlayer _player;
  final AndroidEqualizer? _equalizer;
  final StreamController<String> _playbackErrorController =
      StreamController<String>.broadcast();
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];

  List<MediaItem> _queue = const [];
  int _currentIndex = 0;
  PlaybackEvent? _lastEvent;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;
  AudioServiceShuffleMode _shuffleMode = AudioServiceShuffleMode.none;
  final Map<int, double> _equalizerGainOverrides = <int, double>{};
  bool _equalizerEnabled = true;
  bool _settingQueueSources = false;
  bool _recoveringFromPlaybackError = false;
  bool _disposed = false;
  Future<void> _modeUpdateTail = Future<void>.value();

  AudioPlayer get player => _player;
  int get currentIndex => _currentIndex;
  List<MediaItem> get currentQueue => _queue;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  Stream<String> get playbackErrorStream => _playbackErrorController.stream;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  bool get isPlaying => _player.playing;

  bool get supportsEqualizer => _equalizer != null;
  bool get equalizerEnabled => _equalizerEnabled;

  // ------------------------------------------------------------------- queue
  AudioSource _sourceFor(MediaItem item) {
    final path = _pathOf(item);
    final uri = Uri.tryParse(path);
    if (uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty) {
      return AudioSource.uri(uri, tag: item);
    }
    return AudioSource.file(path, tag: item);
  }

  /// Replaces the whole queue and starts playing [initialIndex].
  Future<void> setQueue(
    List<MediaItem> items, {
    int initialIndex = 0,
    Duration? initialPosition,
    bool autoPlay = true,
  }) async {
    _queue = List<MediaItem>.of(items);
    queue.add(_queue);
    if (_queue.isEmpty) {
      mediaItem.add(null);
      await _player.stop();
      return;
    }
    final safeIndex = initialIndex.clamp(0, _queue.length - 1);
    _currentIndex = safeIndex;
    mediaItem.add(_queue[safeIndex]);

    _settingQueueSources = true;
    try {
      try {
        await _player.setAudioSources(
          _queue.map(_sourceFor).toList(growable: false),
          initialIndex: safeIndex,
          initialPosition: initialPosition,
        );
      } catch (error, stackTrace) {
        final fallback = _withStreamFallback(_queue[safeIndex]);
        if (fallback == null) rethrow;
        _log.w(
          'Could not open the saved file for "${fallback.title}"; trying its provider stream',
          error,
          stackTrace,
        );
        _replaceQueueItem(safeIndex, fallback);
        await _player.setAudioSources(
          _queue.map(_sourceFor).toList(growable: false),
          initialIndex: safeIndex,
          initialPosition: initialPosition,
        );
      }
    } finally {
      _settingQueueSources = false;
    }
    _currentIndex = safeIndex;
    mediaItem.add(_queue[safeIndex]);
    if (autoPlay) {
      await _player.play();
    }
  }

  Future<void> addToQueueEnd(
    List<MediaItem> items, {
    bool playIfEmpty = true,
  }) async {
    if (items.isEmpty) return;
    if (_queue.isEmpty) {
      await setQueue(items, autoPlay: playIfEmpty);
      return;
    }
    await _player.addAudioSources(items.map(_sourceFor).toList());
    _queue = <MediaItem>[..._queue, ...items];
    queue.add(_queue);
  }

  /// Inserts [items] right after the currently playing item.
  Future<void> addNext(List<MediaItem> items) async {
    if (items.isEmpty) return;
    if (_queue.isEmpty) {
      await setQueue(items);
      return;
    }
    var insertAt = _currentIndex + 1;
    for (final item in items) {
      await _player.insertAudioSource(insertAt, _sourceFor(item));
      insertAt++;
    }
    _queue = <MediaItem>[
      ..._queue.take(_currentIndex + 1),
      ...items,
      ..._queue.skip(_currentIndex + 1),
    ];
    queue.add(_queue);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final newQueue = List<MediaItem>.of(_queue)..removeAt(index);
    if (newQueue.isEmpty) {
      await clearQueue();
      return;
    }
    await _player.removeAudioSourceAt(index);
    _queue = newQueue;
    queue.add(_queue);
  }

  Future<void> moveQueueItem(int from, int to) async {
    if (from < 0 ||
        from >= _queue.length ||
        to < 0 ||
        to >= _queue.length ||
        from == to) {
      return;
    }
    await _player.moveAudioSource(from, to);
    final newQueue = List<MediaItem>.of(_queue);
    final item = newQueue.removeAt(from);
    newQueue.insert(to, item);
    _queue = newQueue;
    queue.add(_queue);
  }

  Future<void> clearQueue() async {
    _queue = const [];
    _currentIndex = 0;
    queue.add(const []);
    mediaItem.add(null);
    await _player.stop();
  }

  String _pathOf(MediaItem item) =>
      (item.extras?['path'] as String?) ?? item.id;

  void _onCurrentIndexChanged(int? index) {
    if (index == null || index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) return;
    _currentIndex = index;
    mediaItem.add(_queue[index]);
  }

  void _onPlaybackError(PlayerException error) => _handlePlaybackError(error);

  // -------------------------------------------------------------- transport
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    await _player.seekToNext();
    if (!_player.playing) await _player.play();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    await _player.seekToPrevious();
    if (!_player.playing) await _player.play();
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    await _enqueueModeUpdate(() async {
      switch (repeatMode) {
        case AudioServiceRepeatMode.all:
          await _player.setLoopMode(LoopMode.all);
        case AudioServiceRepeatMode.one:
          await _player.setLoopMode(LoopMode.one);
        case AudioServiceRepeatMode.none:
        case AudioServiceRepeatMode.group:
          await _player.setLoopMode(LoopMode.off);
      }
      _repeatMode = repeatMode;
      _broadcastState();
    });
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    await _enqueueModeUpdate(() async {
      await _player.setShuffleModeEnabled(
        shuffleMode != AudioServiceShuffleMode.none,
      );
      _shuffleMode = shuffleMode;
      _broadcastState();
    });
  }

  Future<void> _enqueueModeUpdate(Future<void> Function() update) {
    if (_disposed) return Future<void>.value();
    final result = _modeUpdateTail.then((_) => update());
    _modeUpdateTail = result.catchError((Object error, StackTrace stackTrace) {
      _log.e('Could not update playback mode', error, stackTrace);
    });
    return result;
  }

  // -------------------------------------------------------------- equalizer
  Future<List<EqualizerBandInfo>> equalizerBands() async {
    final equalizer = _equalizer;
    if (equalizer == null) return const [];
    try {
      final parameters = await equalizer.parameters;
      final bands = <EqualizerBandInfo>[];
      for (var i = 0; i < parameters.bands.length; i++) {
        final band = parameters.bands[i];
        final gain = _equalizerGainOverrides[i] ?? band.gain;
        bands.add(
          EqualizerBandInfo(
            index: i,
            centerFrequency: band.centerFrequency,
            minGain: parameters.minDecibels,
            maxGain: parameters.maxDecibels,
            gain: gain,
          ),
        );
      }
      return bands;
    } catch (error, stackTrace) {
      _log.e('Could not read equalizer bands', error, stackTrace);
      return const [];
    }
  }

  Future<void> setEqualizerEnabled(bool enabled) async {
    final equalizer = _equalizer;
    if (equalizer == null) return;
    _equalizerEnabled = enabled;
    await equalizer.setEnabled(enabled);
  }

  Future<void> setEqualizerGain(int index, double gain) async {
    final equalizer = _equalizer;
    if (equalizer == null) return;
    _equalizerGainOverrides[index] = gain;
    try {
      final parameters = await equalizer.parameters;
      if (index < parameters.bands.length) {
        await parameters.bands[index].setGain(gain);
      }
    } catch (error, stackTrace) {
      _log.e('Could not apply equalizer gain', error, stackTrace);
    }
  }

  Future<void> resetEqualizer() async {
    _equalizerGainOverrides.clear();
    final bands = await equalizerBands();
    for (final band in bands) {
      await setEqualizerGain(band.index, 0);
    }
  }

  // ---------------------------------------------------------------- internals
  void _onPlaybackEvent(PlaybackEvent event) {
    if (_disposed) return;
    _lastEvent = event;
    playbackState.add(_transformEvent(event));
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    _lastEvent = event;
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
      repeatMode: _repeatMode,
      shuffleMode: _shuffleMode,
    );
  }

  void _broadcastState() {
    if (_disposed) return;
    final event = _lastEvent;
    if (event == null) {
      playbackState.add(
        PlaybackState(
          controls: [MediaControl.play],
          androidCompactActionIndices: const [0],
          processingState: AudioProcessingState.idle,
          playing: _player.playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
          repeatMode: _repeatMode,
          shuffleMode: _shuffleMode,
        ),
      );
      return;
    }
    playbackState.add(_transformEvent(event));
  }

  /// Releases the player, event subscriptions, and inherited audio streams.
  /// The provider owner calls this when its application scope is disposed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _modeUpdateTail;
    await Future.wait(_playerSubscriptions.map((subscription) {
      return subscription.cancel();
    }));
    await _player.dispose();
    await _playbackErrorController.close();
    await Future.wait([
      playbackState.close(),
      queue.close(),
      queueTitle.close(),
      mediaItem.close(),
      androidPlaybackInfo.close(),
      ratingStyle.close(),
      customEvent.close(),
      customState.close(),
    ]);
  }
}

/// Creates the audio handler and, on mobile, registers the background service.
Future<NmVibeAudioHandler> initAudioHandler() async {
  await _configureAudioSession();
  if (PlatformInfo.supportsBackgroundAudio) {
    return AudioService.init<NmVibeAudioHandler>(
      builder: () => NmVibeAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.nmvibe.playback',
        androidNotificationChannelName: 'NM VIBE playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  }
  return NmVibeAudioHandler();
}

Future<void> _configureAudioSession() async {
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (error, stackTrace) {
    const AppLogger('AudioSession')
        .w('Audio session configuration unavailable', error, stackTrace);
  }
}
