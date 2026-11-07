import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:nm_vibe/data/downloads/download_task.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/repositories/music_repository.dart';
import 'package:nm_vibe/data/sources/music_source.dart' as source;

/// Coordinates permitted source transfers and persists only verified files.
class DownloadManager {
  DownloadManager({
    required this.musicRepository,
    required this.findSong,
    required this.saveSong,
  });

  // The source storage limit checks a snapshot of on-disk size, so serialize
  // transfers until the storage layer can reserve space across active jobs.
  static const int _maxConcurrentDownloads = 1;

  final MusicRepository musicRepository;
  final Future<Song?> Function(String songId) findSong;
  final Future<void> Function(Song song) saveSong;
  final LinkedHashMap<String, _PendingDownload> _jobs =
      LinkedHashMap<String, _PendingDownload>();
  final Map<String, Future<DownloadJob>> _preparing =
      <String, Future<DownloadJob>>{};
  final Queue<String> _waiting = Queue<String>();
  final Set<String> _active = <String>{};
  final StreamController<List<ManagedDownloadTask>> _changes =
      StreamController<List<ManagedDownloadTask>>.broadcast();
  bool _disposed = false;

  List<ManagedDownloadTask> get tasks =>
      List.unmodifiable(_jobs.values.map((job) => job.state));

  Stream<List<ManagedDownloadTask>> get changes => _changes.stream;

  ManagedDownloadTask? task(String id) => _jobs[id]?.state;

  Stream<ManagedDownloadTask?> watchTask(String id) async* {
    yield task(id);
    yield* changes
        .map((items) {
          for (final item in items) {
            if (item.id == id) return item;
          }
          return null;
        })
        .distinct((previous, current) => identical(previous, current));
  }

  Future<DownloadJob> enqueue(source.MusicTrack track) {
    _checkAlive();
    if (!musicRepository.canDownload(track)) {
      return Future<DownloadJob>.error(
        StateError('This track is not permitted for offline download.'),
      );
    }
    final id = '${track.sourceId}:${track.id}';
    final existingJob = _jobs[id];
    if (existingJob != null &&
        existingJob.state.status != ManagedDownloadStatus.cancelled &&
        existingJob.state.status != ManagedDownloadStatus.failed &&
        existingJob.state.status != ManagedDownloadStatus.completed) {
      return Future<DownloadJob>.value(existingJob.handle);
    }
    final alreadyPreparing = _preparing[id];
    if (alreadyPreparing != null) return alreadyPreparing;
    late final Future<DownloadJob> preparation;
    preparation = _prepare(track).whenComplete(() {
      if (identical(_preparing[id], preparation)) _preparing.remove(id);
    });
    _preparing[id] = preparation;
    return preparation;
  }

  Future<DownloadJob> _prepare(source.MusicTrack track) async {
    final id = '${track.sourceId}:${track.id}';
    final previous = _jobs[id];
    if (previous?.state.status == ManagedDownloadStatus.completed) {
      final previousFile = previous!.state.file;
      if (previousFile != null && await previousFile.exists()) {
        final actualSize = await previousFile.length();
        if (actualSize > 0 &&
            actualSize == previous.state.receivedBytes &&
            (previous.state.totalBytes == null ||
                previous.state.totalBytes == actualSize)) {
          return previous.handle;
        }
      }
      _jobs.remove(id);
    }
    final storedSong = await findSong(track.toSong().id);
    _checkAlive();
    if (storedSong != null && storedSong.isDownloaded) {
      final storedFile = File(storedSong.filePath);
      if (await storedFile.exists()) {
        final actualSize = await storedFile.length();
        final matchesSongRecord = storedSong.fileSize == actualSize;
        if (actualSize > 0 && matchesSongRecord) {
          final pending = _completedJob(track, storedFile);
          _jobs[id] = pending;
          _publish();
          return pending.handle;
        }
      }
    }

    final pending = _newJob(track);
    _jobs[id] = pending;
    _waiting.addLast(id);
    _publish();
    _schedule();
    return pending.handle;
  }

  Future<DownloadJob> retry(String id) async {
    _checkAlive();
    final previous = _jobs[id];
    if (previous == null) {
      throw StateError('Only failed or cancelled downloads can be retried.');
    }
    if (previous.state.status == ManagedDownloadStatus.completed) {
      _jobs.remove(id);
      final pending = _newJob(previous.state.track);
      _jobs[id] = pending;
      _waiting.addLast(id);
      _publish();
      _schedule();
      return pending.handle;
    }
    if (previous.state.status != ManagedDownloadStatus.failed &&
        previous.state.status != ManagedDownloadStatus.cancelled) {
      throw StateError(
        'Only failed, cancelled, or invalid completed downloads can be retried.',
      );
    }
    return enqueue(previous.state.track);
  }

  /// Starts a fresh source transfer for an item with an invalid saved copy.
  Future<DownloadJob> redownload(source.MusicTrack track) async {
    _checkAlive();
    if (!musicRepository.canDownload(track)) {
      throw StateError('This track is not permitted for offline download.');
    }
    final id = '${track.sourceId}:${track.id}';
    final previous = _jobs[id];
    if (previous != null &&
        (previous.state.status == ManagedDownloadStatus.waiting ||
            previous.state.status == ManagedDownloadStatus.downloading)) {
      return previous.handle;
    }
    final preparation = _preparing[id];
    if (preparation != null) {
      final prepared = await preparation;
      final state = _jobs[id]?.state.status;
      if (state == ManagedDownloadStatus.waiting ||
          state == ManagedDownloadStatus.downloading) {
        return prepared;
      }
    }
    _jobs.remove(id);
    final pending = _newJob(track);
    _jobs[id] = pending;
    _waiting.addLast(id);
    _publish();
    _schedule();
    return pending.handle;
  }

  Future<void> cancel(String id) async {
    final pending = _jobs[id];
    if (_disposed || pending == null) return;
    if (pending.state.status == ManagedDownloadStatus.waiting) {
      _waiting.remove(id);
      pending.cancelled = true;
      pending.setState(
        ManagedDownloadTask(
          track: pending.state.track,
          status: ManagedDownloadStatus.cancelled,
        ),
      );
      pending.completeCancelled();
      _publish();
      return;
    }
    if (pending.state.status != ManagedDownloadStatus.downloading) return;
    pending.cancelled = true;
    await pending.sourceTask?.cancel();
  }

  Future<void> cancelAll() async {
    final ids = <String>{..._waiting, ..._active};
    await Future.wait(ids.map(cancel));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await cancelAll();
    for (final id in _waiting.toList(growable: false)) {
      _waiting.remove(id);
      final pending = _jobs[id];
      if (pending == null) continue;
      pending.cancelled = true;
      pending.setState(
        ManagedDownloadTask(
          track: pending.state.track,
          status: ManagedDownloadStatus.cancelled,
        ),
      );
      pending.completeCancelled();
    }
    _disposed = true;
    final running = _active
        .map((id) => _jobs[id])
        .whereType<_PendingDownload>();
    for (final pending in running) {
      pending.cancelled = true;
      await pending.sourceTask?.cancel();
    }
    await _changes.close();
  }

  _PendingDownload _newJob(source.MusicTrack track) {
    final state = ManagedDownloadTask(
      track: track,
      status: ManagedDownloadStatus.waiting,
    );
    final pending = _PendingDownload(state);
    unawaited(
      pending.completer.future.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    final handle = DownloadJob(
      id: state.id,
      result: pending.completer.future,
      cancelOperation: () => cancel(state.id),
    );
    pending.handle = handle;
    return pending;
  }

  _PendingDownload _completedJob(source.MusicTrack track, File file) {
    final state = ManagedDownloadTask(
      track: track,
      status: ManagedDownloadStatus.completed,
      receivedBytes: file.lengthSync(),
      totalBytes: file.lengthSync(),
      file: file,
    );
    final pending = _PendingDownload(state);
    pending.completer.complete(file);
    pending.handle = DownloadJob(
      id: state.id,
      result: pending.completer.future,
      cancelOperation: () async {},
    );
    return pending;
  }

  void _schedule() {
    if (_disposed) return;
    while (_active.length < _maxConcurrentDownloads && _waiting.isNotEmpty) {
      final id = _waiting.removeFirst();
      final pending = _jobs[id];
      if (pending == null || pending.cancelled) continue;
      _active.add(id);
      unawaited(_run(pending));
    }
  }

  Future<void> _run(_PendingDownload pending) async {
    final track = pending.state.track;
    pending.setState(
      ManagedDownloadTask(
        track: track,
        status: ManagedDownloadStatus.downloading,
      ),
    );
    _publish();
    try {
      final operation = musicRepository.startDownload(
        track,
        onProgress: (received, total) {
          if (_disposed || pending.cancelled) return;
          pending.setState(
            ManagedDownloadTask(
              track: track,
              status: ManagedDownloadStatus.downloading,
              receivedBytes: received,
              totalBytes: total,
            ),
          );
          _publish();
        },
      );
      pending.sourceTask = operation;
      final file = await operation.result;
      if (pending.cancelled) throw const source.DownloadCancelled();
      final fileSize = await file.length();
      if (!await file.exists() || fileSize <= 0) {
        throw const FileSystemException(
          'Downloaded audio file is empty or missing.',
        );
      }
      final downloadedSong = track.toSong().copyWith(
        filePath: file.path,
        fileSize: fileSize,
        modifiedAt: await file.lastModified(),
        isDownloaded: true,
      );
      await saveSong(downloadedSong);
      pending.setState(
        ManagedDownloadTask(
          track: track,
          status: ManagedDownloadStatus.completed,
          receivedBytes: fileSize,
          totalBytes: fileSize,
          file: file,
        ),
      );
      pending.complete(file);
    } on Object catch (error, stackTrace) {
      if (pending.cancelled || error is source.DownloadCancelled) {
        pending.setState(
          ManagedDownloadTask(
            track: track,
            status: ManagedDownloadStatus.cancelled,
          ),
        );
        pending.completeCancelled();
      } else {
        pending.setState(
          ManagedDownloadTask(
            track: track,
            status: ManagedDownloadStatus.failed,
            error: error,
          ),
        );
        pending.completeError(error, stackTrace);
      }
    } finally {
      pending.sourceTask = null;
      _active.remove(pending.state.id);
      _publish();
      _schedule();
    }
  }

  void _publish() {
    if (!_disposed && !_changes.isClosed) _changes.add(tasks);
  }

  void _checkAlive() {
    if (_disposed) throw StateError('Download manager has been disposed.');
  }
}

class _PendingDownload {
  _PendingDownload(this.state);

  ManagedDownloadTask state;
  final Completer<File> completer = Completer<File>();
  late DownloadJob handle;
  source.DownloadTask? sourceTask;
  bool cancelled = false;

  void setState(ManagedDownloadTask next) => state = next;

  void complete(File file) {
    if (!completer.isCompleted) completer.complete(file);
  }

  void completeCancelled() {
    if (!completer.isCompleted) {
      completer.completeError(const source.DownloadCancelled());
    }
  }

  void completeError(Object error, StackTrace stackTrace) {
    if (!completer.isCompleted) completer.completeError(error, stackTrace);
  }
}
