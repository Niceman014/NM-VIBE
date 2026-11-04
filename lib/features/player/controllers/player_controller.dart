import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/core/audio/audio_handler.dart';
import 'package:nm_vibe/core/utils/logger.dart';
import 'package:nm_vibe/data/models/song_model.dart';

/// Immutable snapshot of everything the player UI needs.
@immutable
class PlayerState {
  const PlayerState({
    this.queue = const <Song>[],
    this.currentIndex = -1,
    this.playing = false,
    this.loading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.shuffleEnabled = false,
    this.speed = 1.0,
    this.sleepTimerRemaining,
    this.error,
  });

  final List<Song> queue;
  final int currentIndex;
  final bool playing;
  final bool loading;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final AudioServiceRepeatMode repeatMode;
  final bool shuffleEnabled;
  final double speed;

  /// Remaining time on the sleep timer, null when no timer is running.
  final Duration? sleepTimerRemaining;

  final String? error;

  bool get hasQueue => queue.isNotEmpty && currentIndex >= 0;
  bool get hasSong => hasQueue && currentIndex < queue.length;

  Song? get current => hasSong ? queue[currentIndex] : null;
  Song? get next => hasSong && currentIndex + 1 < queue.length
      ? queue[currentIndex + 1]
      : null;

  bool get isBuffering => loading;

  double get progress {
    if (duration.inMilliseconds <= 0) return 0;
    final value = position.inMilliseconds / duration.inMilliseconds;
    return value.clamp(0.0, 1.0);
  }

  PlayerState copyWith({
    List<Song>? queue,
    int? currentIndex,
    bool? playing,
    bool? loading,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    AudioServiceRepeatMode? repeatMode,
    bool? shuffleEnabled,
    double? speed,
    Duration? sleepTimerRemaining,
    String? error,
    bool clearSleepTimer = false,
    bool clearError = false,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      playing: playing ?? this.playing,
      loading: loading ?? this.loading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      speed: speed ?? this.speed,
      sleepTimerRemaining: clearSleepTimer
          ? null
          : (sleepTimerRemaining ?? this.sleepTimerRemaining),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Riverpod-facing controller: translates UI intents into audio-handler calls
/// and mirrors the handler's streams into [PlayerState].
class PlayerController extends StateNotifier<PlayerState> {
  PlayerController({required this._handler, required this._repository})
    : super(const PlayerState()) {
    _subscriptions.addAll([
      _handler.playbackState.listen(_onPlaybackState),
      _handler.mediaItem.listen(_onMediaItem),
      _handler.playbackErrorStream.listen(_onPlaybackError),
      _handler.positionStream.listen(_onPosition),
      _handler.durationStream.listen(_onDuration),
      _handler.bufferedPositionStream.listen(_onBuffered),
    ]);
  }

  static const AppLogger _log = AppLogger('PlayerController');

  final NmVibeAudioHandler _handler;
  final LibraryRepository _repository;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _sleepTimer;
  Timer? _playbackErrorTimer;
  String? _lastRecordedSongId;

  NmVibeAudioHandler get handler => _handler;

  void _onPlaybackState(PlaybackState playbackState) {
    if (!mounted) return;
    final queueIndex = playbackState.queueIndex;
    state = state.copyWith(
      playing: playbackState.playing,
      loading:
          playbackState.processingState == AudioProcessingState.loading ||
          playbackState.processingState == AudioProcessingState.buffering,
      repeatMode: playbackState.repeatMode,
      shuffleEnabled: playbackState.shuffleMode != AudioServiceShuffleMode.none,
      currentIndex:
          (queueIndex != null &&
              queueIndex >= 0 &&
              queueIndex < state.queue.length)
          ? queueIndex
          : state.currentIndex,
    );
  }

  void _onPlaybackError(String message) {
    if (!mounted) return;
    _playbackErrorTimer?.cancel();
    state = state.copyWith(loading: false, error: message);
    _playbackErrorTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) state = state.copyWith(clearError: true);
    });
  }

  void _onMediaItem(MediaItem? item) {
    if (!mounted || item == null) return;
    final index = state.queue.indexWhere((song) => song.id == item.id);
    if (index >= 0 && index != state.currentIndex) {
      state = state.copyWith(currentIndex: index);
    }
    final song = index >= 0 ? state.queue[index] : null;
    if (song != null && _lastRecordedSongId != song.id) {
      _lastRecordedSongId = song.id;
      unawaited(
        _repository.recordPlay(song.id).catchError((Object error) {
          _log.w('Could not record play for ${song.id}', error);
        }),
      );
    }
  }

  void _onPosition(Duration position) {
    if (!mounted) return;
    state = state.copyWith(position: position);
    if (position > Duration.zero &&
        state.duration > Duration.zero &&
        (position - state.duration).abs() < const Duration(seconds: 1) &&
        state.current != null) {
      final song = state.current!;
      if (song.duration == Duration.zero) {
        unawaited(_repository.updatePlaybackInfo(song.id, state.duration));
      }
    }
  }

  void _onDuration(Duration? duration) {
    if (!mounted || duration == null) return;
    state = state.copyWith(duration: duration);
  }

  void _onBuffered(Duration buffered) {
    if (!mounted) return;
    state = state.copyWith(buffered: buffered);
  }

  // -------------------------------------------------------------- queue API
  Future<void> playSongs(
    List<Song> songs, {
    int initialIndex = 0,
    Duration? initialPosition,
    bool autoPlay = true,
  }) async {
    if (songs.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, songs.length - 1);
    _lastRecordedSongId = null;
    state = state.copyWith(
      queue: List<Song>.of(songs),
      currentIndex: safeIndex,
      loading: true,
      position: initialPosition ?? Duration.zero,
      duration: songs[safeIndex].duration,
      clearError: true,
    );
    try {
      await _handler.setQueue(
        songs.map(_toMediaItem).toList(growable: false),
        initialIndex: safeIndex,
        initialPosition: initialPosition,
        autoPlay: autoPlay,
      );
    } catch (error, stackTrace) {
      _log.e('Could not start playback', error, stackTrace);
      if (!mounted) return;
      state = state.copyWith(loading: false, error: '$error');
    }
  }

  Future<void> playSong(Song song, {List<Song>? context}) async {
    final songs = context == null || context.isEmpty ? <Song>[song] : context;
    final index = songs.indexWhere((item) => item.id == song.id);
    await playSongs(songs, initialIndex: index < 0 ? 0 : index);
  }

  Future<void> togglePlayPause() async {
    if (!state.hasSong) return;
    try {
      if (state.playing) {
        await _handler.pause();
      } else {
        await _handler.play();
      }
    } catch (error, stackTrace) {
      _log.e('Could not change playback state', error, stackTrace);
      if (mounted) {
        state = state.copyWith(loading: false, error: '$error');
      }
    }
  }

  Future<void> next() => _handler.skipToNext();

  Future<void> previous() => _handler.skipToPrevious();

  Future<void> seek(Duration position) async {
    final target = position < Duration.zero
        ? Duration.zero
        : (state.duration > Duration.zero && position > state.duration
              ? state.duration
              : position);
    state = state.copyWith(position: target);
    await _handler.seek(target);
  }

  Future<void> setSpeed(double speed) async {
    await _handler.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  Future<void> cycleRepeatMode() async {
    final next = switch (state.repeatMode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      AudioServiceRepeatMode.one => AudioServiceRepeatMode.none,
      AudioServiceRepeatMode.group => AudioServiceRepeatMode.none,
    };
    await _handler.setRepeatMode(next);
    state = state.copyWith(repeatMode: next);
  }

  Future<void> toggleShuffle() async {
    final enabled = !state.shuffleEnabled;
    await _handler.setShuffleMode(
      enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
    state = state.copyWith(shuffleEnabled: enabled);
  }

  Future<void> addToQueue(Song song) async {
    if (!state.hasQueue) {
      await playSongs(<Song>[song]);
      return;
    }
    await _handler.addToQueueEnd(<MediaItem>[_toMediaItem(song)]);
    state = state.copyWith(queue: <Song>[...state.queue, song]);
  }

  Future<void> playNext(Song song) async {
    if (!state.hasQueue) {
      await playSongs(<Song>[song]);
      return;
    }
    final queue = List<Song>.of(state.queue)
      ..insert((state.currentIndex + 1).clamp(0, state.queue.length), song);
    await _handler.addNext(<MediaItem>[_toMediaItem(song)]);
    state = state.copyWith(queue: queue);
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= state.queue.length) return;
    final queue = List<Song>.of(state.queue)..removeAt(index);
    await _handler.removeQueueItemAt(index);
    if (queue.isEmpty) {
      state = const PlayerState();
      return;
    }
    final shiftedIndex = index < state.currentIndex
        ? state.currentIndex - 1
        : (index == state.currentIndex
              ? state.currentIndex.clamp(0, queue.length - 1)
              : state.currentIndex);
    state = state.copyWith(queue: queue, currentIndex: shiftedIndex);
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.queue.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= state.queue.length || target == oldIndex) {
      return;
    }
    final currentId = state.current?.id;
    final queue = List<Song>.of(state.queue);
    final song = queue.removeAt(oldIndex);
    queue.insert(target, song);
    await _handler.moveQueueItem(oldIndex, target);
    final currentIndex = currentId == null
        ? state.currentIndex
        : queue.indexWhere((s) => s.id == currentId);
    state = state.copyWith(
      queue: queue,
      currentIndex: currentIndex < 0 ? state.currentIndex : currentIndex,
    );
  }

  Future<void> clearQueue() async {
    await _handler.stop();
    await _handler.clearQueue();
    _cancelSleepTimer();
    state = const PlayerState();
  }

  // ------------------------------------------------------------ sleep timer
  void setSleepTimer(Duration? duration) {
    _cancelSleepTimer();
    if (duration == null) {
      state = state.copyWith(clearSleepTimer: true);
      return;
    }
    state = state.copyWith(sleepTimerRemaining: duration);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.sleepTimerRemaining;
      if (remaining == null) {
        timer.cancel();
        return;
      }
      final next = remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        timer.cancel();
        state = state.copyWith(clearSleepTimer: true);
        if (state.playing) {
          unawaited(_handler.pause());
        }
      } else {
        state = state.copyWith(sleepTimerRemaining: next);
      }
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
  }

  MediaItem _toMediaItem(Song song) {
    return MediaItem(
      id: song.id,
      title: song.displayTitle,
      artist: song.displayArtist,
      album: song.displayAlbum,
      duration: song.duration,
      extras: <String, dynamic>{
        'path': song.isDownloaded
            ? song.filePath
            : (song.streamUrl ?? song.filePath),
        'artworkKey': song.artworkKey,
        'artworkUrl': song.remoteArtworkUrl,
        'source': song.source,
      },
    );
  }

  @override
  void dispose() {
    _cancelSleepTimer();
    _playbackErrorTimer?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
