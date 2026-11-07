import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:nm_vibe/data/models/song_model.dart';

class PlaybackRecoveryException implements Exception {
  const PlaybackRecoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

String playbackFailureMessage(Object error) {
  if (error is PlaybackRecoveryException) return error.message;
  return 'Could not play this track. Check the file or your connection.';
}

/// Resolves a downloaded song to a usable local file or its original provider
/// stream. Download permission is deliberately not used as a streaming grant.
Future<Song> prepareSongForPlayback(
  Song song, {
  Future<bool> Function(String path)? isUsableFile,
}) async {
  if (!song.isDownloaded) return song;

  final localFileIsUsable = await (isUsableFile ?? _isUsableFile)(
    song.filePath,
  );
  if (localFileIsUsable) return song;

  final streamUri = _permittedStreamUri(song);
  if (streamUri == null) {
    throw PlaybackRecoveryException(
      'The downloaded file for "${song.displayTitle}" is unavailable, '
      'and this track has no usable provider stream.',
    );
  }

  return song.copyWith(filePath: streamUri.toString(), isDownloaded: false);
}

/// Returns the known provider's stream URL for decoder-error recovery.
String? permittedStreamFallbackUrlFor(Song song) =>
    _permittedStreamUri(song)?.toString();

MediaItem mediaItemForSong(Song song) => MediaItem(
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
    'isDownloaded': song.isDownloaded,
    'fallbackStreamUrl': song.isDownloaded
        ? permittedStreamFallbackUrlFor(song)
        : null,
  },
);

Future<bool> _isUsableFile(String path) async {
  try {
    final file = File(path);
    return await file.exists() && await file.length() > 0;
  } on FileSystemException {
    return false;
  }
}

Uri? _permittedStreamUri(Song song) {
  final source = song.source;
  if (source != 'internet_archive') return null;
  final idSeparator = song.id.indexOf(':');
  if (idSeparator <= 0 || song.id.substring(0, idSeparator) != source) {
    return null;
  }

  final uri = Uri.tryParse(song.streamUrl ?? '');
  if (uri == null || uri.scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  final validHost = switch (source) {
    'internet_archive' =>
      host == 'archive.org' || host.endsWith('.archive.org'),
    _ => false,
  };
  return validHost ? uri : null;
}
