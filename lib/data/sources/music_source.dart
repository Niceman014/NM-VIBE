import 'dart:io';

import 'package:nm_vibe/data/models/song_model.dart';

/// A remote catalog row that the player and UI can handle without knowing the
/// source's API response shape.
abstract interface class MusicTrack {
  String get sourceId;
  String get id;
  String get title;
  String get artist;
  String get album;
  Duration get duration;
  String get streamUrl;
  String? get downloadUrl;
  String? get artworkUrl;
  String? get licenseUrl;
  String? get pageUrl;
  bool get downloadAllowed;
  String? get codec;
  int? get bitrateKbps;

  Song toSong();
}

/// Adapter contract for a single music catalog or the local library.
abstract interface class MusicSource {
  String get id;
  bool get isConfigured;
  bool get canDownload;

  Future<List<MusicTrack>> search(String query, {required int page});
  Future<String?> getStreamUrl(String trackId);
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  });
  String attributionFor(MusicTrack track);
  void close();
}

typedef DownloadProgressCallback = void Function(int receivedBytes, int? totalBytes);

final class DownloadTask {
  const DownloadTask(this.result, this._cancel);

  final Future<File> result;
  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

final class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'Download cancelled';
}
