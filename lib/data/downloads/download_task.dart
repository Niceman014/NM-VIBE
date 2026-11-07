import 'dart:io';

import 'package:nm_vibe/data/sources/music_source.dart';

enum ManagedDownloadStatus {
  waiting,
  downloading,
  completed,
  failed,
  cancelled,
}

class ManagedDownloadTask {
  const ManagedDownloadTask({
    required this.track,
    required this.status,
    this.receivedBytes = 0,
    this.totalBytes,
    this.file,
    this.error,
  });

  final MusicTrack track;
  final ManagedDownloadStatus status;
  final int receivedBytes;
  final int? totalBytes;
  final File? file;
  final Object? error;

  String get id => '${track.sourceId}:${track.id}';

  double? get progress => totalBytes == null || totalBytes! <= 0
      ? null
      : (receivedBytes / totalBytes!).clamp(0, 1).toDouble();
}

/// Handle returned to the caller so it can await, observe, or cancel a job.
class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.result,
    required this.cancelOperation,
  });

  final String id;
  final Future<File> result;
  final Future<void> Function() cancelOperation;

  Future<void> cancel() => cancelOperation();
}
