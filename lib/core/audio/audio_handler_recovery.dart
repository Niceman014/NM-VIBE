part of 'audio_handler.dart';

extension _AudioHandlerRecovery on NmVibeAudioHandler {
  void _handlePlaybackError(PlayerException error) {
    if (_disposed || _settingQueueSources || _recoveringFromPlaybackError) {
      return;
    }
    final failedIndex = error.index ?? _player.currentIndex ?? _currentIndex;
    if (failedIndex < 0 || failedIndex >= _queue.length) {
      unawaited(_reportPlaybackError(null, error));
      return;
    }
    final fallback = _withStreamFallback(_queue[failedIndex]);
    if (fallback != null) {
      unawaited(_recoverWithStream(failedIndex, fallback, error));
      return;
    }
    unawaited(_reportPlaybackError(_queue[failedIndex], error));
  }

  MediaItem? _withStreamFallback(MediaItem item) {
    final extras = item.extras;
    if (extras?['isDownloaded'] != true) return null;
    final source = extras?['source'];
    final stream = extras?['fallbackStreamUrl'];
    if (source is! String || stream is! String) return null;
    final separator = item.id.indexOf(':');
    if (separator <= 0 || item.id.substring(0, separator) != source) {
      return null;
    }
    final uri = Uri.tryParse(stream);
    if (uri == null || uri.scheme != 'https') return null;
    final host = uri.host.toLowerCase();
    final validHost = switch (source) {
      'internet_archive' =>
        host == 'archive.org' || host.endsWith('.archive.org'),
      _ => false,
    };
    if (!validHost) return null;
    return item.copyWith(
      extras: <String, dynamic>{
        ...extras!,
        'path': uri.toString(),
        'isDownloaded': false,
        'downloadFallback': true,
        'fallbackStreamUrl': null,
      },
    );
  }

  void _replaceQueueItem(int index, MediaItem item) {
    final updated = List<MediaItem>.of(_queue)..[index] = item;
    _queue = updated;
    queue.add(_queue);
    mediaItem.add(item);
  }

  Future<void> _recoverWithStream(
    int failedIndex,
    MediaItem fallback,
    Object error,
  ) async {
    if (_disposed) return;
    _recoveringFromPlaybackError = true;
    final failed = _queue[failedIndex];
    NmVibeAudioHandler._log.w(
      'Saved file failed for "${failed.title}"; trying its provider stream',
      error,
    );
    _replaceQueueItem(failedIndex, fallback);
    try {
      await _player.setAudioSources(
        _queue.map(_sourceFor).toList(growable: false),
        initialIndex: failedIndex,
        initialPosition: Duration.zero,
      );
      _currentIndex = failedIndex;
      unawaited(
        _player.play().catchError((Object streamError, StackTrace trace) {
          NmVibeAudioHandler._log.e(
            'Provider stream playback failed for "${failed.title}"',
            streamError,
            trace,
          );
          unawaited(
            _reportPlaybackError(fallback, streamError, stackTrace: trace),
          );
        }),
      );
    } catch (streamError, stackTrace) {
      NmVibeAudioHandler._log.e(
        'Provider stream fallback failed for "${failed.title}"',
        streamError,
        stackTrace,
      );
      await _reportPlaybackError(fallback, streamError, stackTrace: stackTrace);
    } finally {
      _recoveringFromPlaybackError = false;
    }
  }

  Future<void> _reportPlaybackError(
    MediaItem? item,
    Object error, {
    StackTrace? stackTrace,
  }) async {
    if (_disposed) return;
    final title = item?.title;
    NmVibeAudioHandler._log.e(
      title == null ? 'Audio playback failed' : 'Playback failed for "$title"',
      error,
      stackTrace,
    );
    try {
      await _player.pause();
    } catch (pauseError, pauseStackTrace) {
      NmVibeAudioHandler._log.e(
        'Could not pause after a playback error',
        pauseError,
        pauseStackTrace,
      );
    }
    if (_disposed) return;
    _playbackErrorController.add(
      title == null
          ? 'Could not play this track. Check the file or your connection.'
          : 'Could not play "$title". Retry or skip to another track.',
    );
  }
}
