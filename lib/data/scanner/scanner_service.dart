import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/core/constants/app_constants.dart';
import 'package:nm_vibe/data/repositories/library_repository.dart';
import 'package:nm_vibe/core/utils/logger.dart';
import 'package:nm_vibe/core/scanner/artwork_service.dart';
import 'package:nm_vibe/core/scanner/tags/tag_reader.dart';

/// Receives coarse scan progress. [processed] can equal [total] when done.
class ScanProgress {
  const ScanProgress({
    required this.processed,
    required this.total,
    this.currentFile,
  });

  final int processed;
  final int total;
  final String? currentFile;

  double get fraction => total <= 0 ? 0.0 : (processed / total).clamp(0.0, 1.0);
}

typedef ScanProgressCallback = void Function(ScanProgress progress);

/// Thrown by [AndroidMediaStoreScanner] when the storage permission is denied.
class ScanPermissionException implements Exception {
  const ScanPermissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One source of songs: a desktop folder walk or the Android MediaStore.
abstract class ScanSource {
  /// Human readable name, used for logs and error messages.
  String get name;

  /// Returns every song [this] source can currently see.
  Future<List<Song>> scan({ScanProgressCallback? onProgress});
}

/// Result of merging a scan into the existing library.
class ScanMergeResult {
  const ScanMergeResult({
    required this.songs,
    required this.added,
    required this.updated,
    required this.removed,
  });

  /// The merged library contents, in scan order.
  final List<Song> songs;
  final int added;
  final int updated;
  final int removed;
}

/// Merges freshly scanned songs into [repository].
///
/// User-owned metadata (`isFavorite`, `playCount`, `lastPlayedAt`, `addedAt`)
/// is always preserved for songs whose id already exists. Stale songs — files
/// that disappeared — are only removed when [fullRefresh] is true, so an
/// incremental scan of one folder never drops the rest of the library.
Future<ScanMergeResult> applyScanResults(
  LibraryRepository repository,
  List<Song> scanned, {
  required bool fullRefresh,
}) async {
  final existingSongs = await repository.getSongs();
  final existing = <String, Song>{
    for (final song in existingSongs) song.id: song,
  };

  final merged = <Song>[];
  final seen = <String>{};
  var added = 0;
  var updated = 0;

  for (final fresh in scanned) {
    if (!seen.add(fresh.id)) continue; // duplicate paths / sources
    final old = existing[fresh.id];
    if (old == null) {
      added++;
      merged.add(fresh);
      continue;
    }
    final next = fresh.copyWith(
      addedAt: old.addedAt,
      playCount: old.playCount,
      lastPlayedAt: old.lastPlayedAt,
      isFavorite: old.isFavorite,
      artworkKey: fresh.artworkKey ?? old.artworkKey,
      source: old.source,
      streamUrl: old.streamUrl,
      downloadUrl: old.downloadUrl,
      externalPageUrl: old.externalPageUrl,
      licenseUrl: old.licenseUrl,
      remoteArtworkUrl: old.remoteArtworkUrl,
      downloadAllowed: old.downloadAllowed,
      isDownloaded: old.isDownloaded,
    );
    if (!_sameMetadata(old, next)) updated++;
    merged.add(next);
  }

  if (fullRefresh) {
    for (final old in existingSongs) {
      if (!old.isDownloaded || seen.contains(old.id)) continue;
      if (!await File(old.filePath).exists()) continue;
      seen.add(old.id);
      merged.add(old);
    }
  }

  final keepIds = merged.map((song) => song.id).toSet();
  var removed = 0;
  if (fullRefresh) {
    for (final id in existing.keys) {
      if (!keepIds.contains(id)) removed++;
    }
  }

  await repository.saveSongs(merged);
  if (fullRefresh) await repository.deleteSongsNotIn(keepIds);

  return ScanMergeResult(
    songs: merged,
    added: added,
    updated: updated,
    removed: removed,
  );
}

bool _sameMetadata(Song a, Song b) {
  return a.filePath == b.filePath &&
      a.title == b.title &&
      a.artist == b.artist &&
      a.album == b.album &&
      a.albumArtist == b.albumArtist &&
      a.genre == b.genre &&
      a.year == b.year &&
      a.trackNumber == b.trackNumber &&
      a.discNumber == b.discNumber &&
      a.duration == b.duration &&
      a.fileSize == b.fileSize &&
      a.modifiedAt == b.modifiedAt &&
      a.artworkKey == b.artworkKey &&
      a.source == b.source &&
      a.streamUrl == b.streamUrl &&
      a.downloadUrl == b.downloadUrl &&
      a.externalPageUrl == b.externalPageUrl &&
      a.licenseUrl == b.licenseUrl &&
      a.remoteArtworkUrl == b.remoteArtworkUrl &&
      a.downloadAllowed == b.downloadAllowed &&
      a.isDownloaded == b.isDownloaded;
}

/// Stable song id: sha1 of the canonical, lower-cased file path.
String songIdForPath(String filePath) {
  final normalised = p.normalize(filePath).toLowerCase();
  return sha1.convert(utf8.encode(normalised)).toString();
}

/// Artwork cache key: sha1 of the lower-cased album artist + album pair.
/// Songs without an album fall back to their own id so they still get artwork.
String artworkKeyFor({
  required String albumArtist,
  required String album,
  required String songId,
}) {
  final albumName = album.trim().toLowerCase();
  if (albumName.isEmpty) return songId;
  final artistName = albumArtist.trim().toLowerCase();
  return sha1.convert(utf8.encode('$artistName\u0001$albumName')).toString();
}

/// Parts derived from a file name such as `Artist - Title.mp3`.
class FilenameTags {
  const FilenameTags({this.artist, required this.title, this.trackNumber});

  final String? artist;
  final String title;
  final int? trackNumber;
}

/// Extracts an artist/title/track-number fallback from a file name.
///
/// Handles `Artist - Title`, `01 Artist - Title`, `01. Artist - Title` and
/// leaves a plain file name as the title.
FilenameTags parseFilenameTags(String fileNameWithoutExtension) {
  var working = fileNameWithoutExtension.trim();
  if (working.isEmpty) {
    return const FilenameTags(title: '');
  }

  int? trackNumber;
  final trackMatch = RegExp(r'^(\d{1,3})\s*[.\-_)\]]?\s*').firstMatch(working);
  if (trackMatch != null) {
    final number = int.tryParse(trackMatch.group(1)!);
    final remainder = working.substring(trackMatch.end).trim();
    if (number != null && number > 0 && remainder.isNotEmpty) {
      trackNumber = number;
      working = remainder;
    }
  }

  final separator = RegExp(r'\s+[-\u2013\u2014]\s+').firstMatch(working);
  if (separator != null) {
    final artist = working.substring(0, separator.start).trim();
    final title = working.substring(separator.end).trim();
    if (artist.isNotEmpty && title.isNotEmpty) {
      return FilenameTags(
        artist: artist,
        title: title,
        trackNumber: trackNumber,
      );
    }
  }
  return FilenameTags(title: working, trackNumber: trackNumber);
}

/// Candidate default music folders for the current user (existing only).
List<String> defaultMusicFolders() {
  final environment = Platform.environment;
  final home = environment['USERPROFILE'] ?? environment['HOME'];
  final candidates = <String>[];
  if (home != null && home.trim().isNotEmpty) {
    for (final name in AppConstants.desktopMusicFolderNames) {
      candidates.add(p.join(home, name));
    }
  }
  final xdg = environment['XDG_MUSIC_DIR'];
  if (xdg != null && xdg.trim().isNotEmpty) {
    candidates.add(xdg.startsWith('file://') ? xdg.substring(7) : xdg);
  }
  return _existingDirectories(candidates);
}

List<String> _existingDirectories(Iterable<String> candidates) {
  final result = <String>[];
  final seen = <String>{};
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isEmpty) continue;
    final directory = Directory(trimmed);
    if (!directory.existsSync()) continue;
    final canonical = _canonicalDirectoryPath(directory);
    if (seen.add(canonical.toLowerCase())) result.add(canonical);
  }
  return result;
}

String _canonicalDirectoryPath(Directory directory) {
  try {
    final resolved = directory.resolveSymbolicLinksSync();
    if (resolved.isNotEmpty) return p.normalize(resolved);
  } catch (_) {
    // Fall back to the plain absolute path.
  }
  return p.normalize(directory.absolute.path);
}

/// Desktop scanner: recursively walks the configured folders (or the user's
/// Music folder when none are configured) and reads embedded tags.
class DesktopFolderScanner implements ScanSource {
  DesktopFolderScanner({
    required this._artworkService,
    List<String> folders = const <String>[],
    TagReader? tagReader,
  }) : _folders = List<String>.unmodifiable(folders),
       _tagReader = tagReader ?? const TagReader();

  static const AppLogger _log = AppLogger('DesktopScanner');
  static const int _maxFiles = 100000;
  static const int _maxEntries = 500000;
  static const int _maxCoverBytes = 10 * 1024 * 1024;
  static const Set<String> _skippedDirectoryNames = <String>{
    'system volume information',
    '\$recycle.bin',
    '\$windows.~bt',
    'recycler',
    'lost+found',
  };

  final ArtworkService _artworkService;
  final List<String> _folders;
  final TagReader _tagReader;

  @override
  String get name => 'Desktop folder scan';

  @override
  Future<List<Song>> scan({ScanProgressCallback? onProgress}) async {
    final roots = _resolveRoots();
    if (roots.isEmpty) {
      onProgress?.call(const ScanProgress(processed: 0, total: 0));
      return <Song>[];
    }

    // Let the library show its scanning state before touching a large or slow
    // removable/network folder.
    onProgress?.call(const ScanProgress(processed: 0, total: 0));
    final files = await _collectAudioFiles(roots);
    final total = files.length;
    final songs = <Song>[];
    if (total == 0) {
      onProgress?.call(const ScanProgress(processed: 0, total: 0));
      return songs;
    }
    onProgress?.call(ScanProgress(processed: 0, total: total));

    final artworkCache = <String, bool>{};
    final coverCache = <String, Uint8List?>{};
    for (var i = 0; i < files.length; i++) {
      final file = files[i];
      try {
        final song = await _readSong(file, artworkCache, coverCache);
        songs.add(song);
      } catch (error, stackTrace) {
        _log.w('Could not scan ${file.path}', error, stackTrace);
      }
      onProgress?.call(
        ScanProgress(processed: i + 1, total: total, currentFile: file.path),
      );
      // Let the UI breathe on very large libraries.
      if (i % 20 == 19) await Future<void>.delayed(Duration.zero);
    }
    return songs;
  }

  List<String> _resolveRoots() {
    final configured = _existingDirectories(_folders);
    if (configured.isNotEmpty) return configured;
    return defaultMusicFolders();
  }

  Future<List<File>> _collectAudioFiles(List<String> roots) async {
    final files = <File>[];
    final seenFiles = <String>{};
    final visitedDirectories = <String>{};
    var visitedEntries = 0;

    for (final root in roots) {
      final rootDirectory = Directory(root);
      if (!await rootDirectory.exists()) continue;
      final stack = <Directory>[rootDirectory];
      while (stack.isNotEmpty &&
          files.length < _maxFiles &&
          visitedEntries < _maxEntries) {
        final directory = stack.removeLast();
        final canonical = p.normalize(directory.absolute.path);
        if (!visitedDirectories.add(canonical.toLowerCase())) continue;

        try {
          await for (final entity in directory.list(followLinks: false)) {
            visitedEntries++;
            if (entity is Directory) {
              if (!_shouldSkipDirectory(entity.path)) stack.add(entity);
            } else if (entity is File && _isAudioFile(entity.path)) {
              final normalised = p.normalize(entity.path).toLowerCase();
              if (seenFiles.add(normalised)) files.add(entity);
            }

            // Bound work between frames even when a folder contains millions
            // of unrelated files or a slow network directory.
            if (visitedEntries % 256 == 0) {
              await Future<void>.delayed(Duration.zero);
            }
            if (files.length >= _maxFiles || visitedEntries >= _maxEntries) {
              break;
            }
          }
        } catch (error, stackTrace) {
          _log.w('Could not list ${directory.path}', error, stackTrace);
        }
      }
    }

    if (files.length >= _maxFiles || visitedEntries >= _maxEntries) {
      _log.w(
        'Stopped scanning at configured safety limit '
        '($_maxFiles audio files, $_maxEntries filesystem entries)',
      );
    }

    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return files;
  }

  bool _shouldSkipDirectory(String path) {
    final name = p.basename(path);
    if (name.isEmpty || name.startsWith('.')) return true;
    return _skippedDirectoryNames.contains(name.toLowerCase());
  }

  bool _isAudioFile(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension.isNotEmpty &&
        AppConstants.audioExtensions.contains(extension);
  }

  Future<Song> _readSong(
    File file,
    Map<String, bool> artworkCache,
    Map<String, Uint8List?> coverCache,
  ) async {
    final stat = file.statSync();
    final path = _canonicalFilePath(file);
    final id = songIdForPath(path);
    final tags = _tagReader.read(file);
    final fallback = parseFilenameTags(p.basenameWithoutExtension(path));

    final title = _nonEmpty(tags.title) ?? fallback.title;
    final artist = _nonEmpty(tags.artist) ?? fallback.artist ?? '';
    final folderName = p.basename(p.dirname(path));
    final album = _nonEmpty(tags.album) ?? folderName;
    final albumArtist = _nonEmpty(tags.albumArtist) ?? artist;

    final artworkKey = artworkKeyFor(
      albumArtist: albumArtist,
      album: album,
      songId: id,
    );
    final hasArtwork = await _ensureArtwork(
      tags: tags,
      directory: file.parent,
      artworkKey: artworkKey,
      artworkCache: artworkCache,
      coverCache: coverCache,
    );

    return Song(
      id: id,
      filePath: path,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      genre: _nonEmpty(tags.genre),
      year: tags.year,
      trackNumber: tags.trackNumber ?? fallback.trackNumber,
      discNumber: tags.discNumber,
      duration: tags.duration ?? Duration.zero,
      fileSize: stat.size,
      addedAt: DateTime.now(),
      modifiedAt: stat.modified,
      artworkKey: hasArtwork ? artworkKey : null,
    );
  }

  Future<bool> _ensureArtwork({
    required AudioTags tags,
    required Directory directory,
    required String artworkKey,
    required Map<String, bool> artworkCache,
    required Map<String, Uint8List?> coverCache,
  }) async {
    final cached = artworkCache[artworkKey];
    if (cached != null) return cached;

    Uint8List? bytes = tags.picture;
    bytes ??= await _folderCover(directory, coverCache);

    var success = false;
    if (bytes != null && bytes.isNotEmpty) {
      try {
        success = await _artworkService.cacheArtwork(artworkKey, bytes) != null;
      } catch (error, stackTrace) {
        _log.w('Could not cache artwork $artworkKey', error, stackTrace);
      }
    }
    artworkCache[artworkKey] = success;
    return success;
  }

  Future<Uint8List?> _folderCover(
    Directory directory,
    Map<String, Uint8List?> coverCache,
  ) async {
    final cacheKey = directory.path.toLowerCase();
    if (coverCache.containsKey(cacheKey)) return coverCache[cacheKey];
    Uint8List? bytes;
    try {
      for (final name in AppConstants.artworkFileNames) {
        final file = File(p.join(directory.path, name));
        if (!file.existsSync()) continue;
        final stat = file.statSync();
        if (stat.size <= 0 || stat.size > _maxCoverBytes) continue;
        final read = file.readAsBytesSync();
        if (read.isNotEmpty) {
          bytes = read;
          break;
        }
      }
    } catch (error, stackTrace) {
      _log.w(
        'Could not read folder artwork in ${directory.path}',
        error,
        stackTrace,
      );
    }
    coverCache[cacheKey] = bytes;
    return bytes;
  }

  String _canonicalFilePath(File file) {
    try {
      final resolved = file.resolveSymbolicLinksSync();
      if (resolved.isNotEmpty) return p.normalize(resolved);
    } catch (_) {
      // Fall back to the plain absolute path.
    }
    return p.normalize(file.absolute.path);
  }
}

/// Android (MediaStore) scanner powered by `on_audio_query`.
///
/// The plugin needs `READ_MEDIA_AUDIO` on Android 13+ / `READ_EXTERNAL_STORAGE`
/// on older releases (declared in AndroidManifest.xml, owned by audio-platform).
class AndroidMediaStoreScanner implements ScanSource {
  AndroidMediaStoreScanner({
    required this._artworkService,
    OnAudioQuery? audioQuery,
  }) : _query = audioQuery ?? OnAudioQuery();

  static const AppLogger _log = AppLogger('MediaStore');

  final ArtworkService _artworkService;
  final OnAudioQuery _query;

  @override
  String get name => 'Android MediaStore scan';

  /// Checks and, when needed, requests the storage permission.
  Future<bool> ensurePermission() async {
    try {
      return await _query.checkAndRequest(retryRequest: true);
    } catch (error, stackTrace) {
      _log.w('Permission request failed', error, stackTrace);
      return false;
    }
  }

  @override
  Future<List<Song>> scan({ScanProgressCallback? onProgress}) async {
    final granted = await ensurePermission();
    if (!granted) {
      throw const ScanPermissionException(
        'Storage permission was denied. Allow music access to scan the library.',
      );
    }

    List<SongModel> models;
    try {
      models = await _query.querySongs(uriType: UriType.EXTERNAL);
    } catch (error, stackTrace) {
      _log.w('MediaStore song query failed', error, stackTrace);
      throw const ScanPermissionException(
        'Could not read the device music library.',
      );
    }

    final albumsById = <int, AlbumModel>{};
    try {
      final albums = await _query.queryAlbums(uriType: UriType.EXTERNAL);
      for (final album in albums) {
        albumsById[album.id] = album;
      }
    } catch (error, stackTrace) {
      // Album data is optional: artwork and album artist just stay empty.
      _log.w('MediaStore album query failed', error, stackTrace);
    }

    final total = models.length;
    final songs = <Song>[];
    final artworkCache = <String, bool>{};
    onProgress?.call(ScanProgress(processed: 0, total: total));

    for (var i = 0; i < models.length; i++) {
      final model = models[i];
      try {
        final song = await _songFromModel(model, albumsById, artworkCache);
        if (song != null) songs.add(song);
      } catch (error, stackTrace) {
        _log.w('Could not map MediaStore song ${model.id}', error, stackTrace);
      }
      onProgress?.call(
        ScanProgress(processed: i + 1, total: total, currentFile: model.data),
      );
      if (i % 20 == 19) await Future<void>.delayed(Duration.zero);
    }
    return songs;
  }

  Future<Song?> _songFromModel(
    SongModel model,
    Map<int, AlbumModel> albumsById,
    Map<String, bool> artworkCache,
  ) async {
    final path = p.normalize(model.data);
    if (path.isEmpty) return null;
    final id = songIdForPath(path);
    final fallback = parseFilenameTags(model.displayNameWOExt);

    final albumModel = albumsById[model.albumId];
    final title = _nonEmpty(model.title) ?? fallback.title;
    final album = _nonEmpty(model.album) ?? _nonEmpty(albumModel?.album) ?? '';
    final albumArtist =
        _nonEmpty(albumModel?.artist) ?? _nonEmpty(model.artist) ?? '';
    final artist = _nonEmpty(model.artist) ?? albumArtist;

    final artworkKey = artworkKeyFor(
      albumArtist: albumArtist,
      album: album,
      songId: id,
    );
    final hasArtwork = await _ensureArtwork(
      key: artworkKey,
      model: model,
      artworkCache: artworkCache,
    );

    final durationMs = model.duration ?? 0;
    return Song(
      id: id,
      filePath: path,
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      genre: _nonEmpty(model.genre),
      year: null,
      trackNumber: (model.track ?? 0) > 0 ? model.track : null,
      discNumber: null,
      duration: Duration(milliseconds: math.max(0, durationMs)),
      fileSize: model.size,
      addedAt: _dateFromEpochSeconds(model.dateAdded),
      modifiedAt: model.dateModified == null
          ? null
          : _dateFromEpochSeconds(model.dateModified),
      artworkKey: hasArtwork ? artworkKey : null,
    );
  }

  Future<bool> _ensureArtwork({
    required String key,
    required SongModel model,
    required Map<String, bool> artworkCache,
  }) async {
    final cached = artworkCache[key];
    if (cached != null) return cached;

    Uint8List? bytes;
    try {
      if (model.albumId != null) {
        bytes = await _query.queryArtwork(
          model.albumId!,
          ArtworkType.ALBUM,
          format: ArtworkFormat.JPEG,
          size: 500,
        );
      }
      if (bytes == null || bytes.isEmpty) {
        bytes = await _query.queryArtwork(
          model.id,
          ArtworkType.AUDIO,
          format: ArtworkFormat.JPEG,
          size: 500,
        );
      }
    } catch (error, stackTrace) {
      _log.w('Could not load artwork for song ${model.id}', error, stackTrace);
      bytes = null;
    }

    var success = false;
    if (bytes != null && bytes.isNotEmpty) {
      try {
        success = await _artworkService.cacheArtwork(key, bytes) != null;
      } catch (error, stackTrace) {
        _log.w('Could not cache artwork $key', error, stackTrace);
      }
    }
    artworkCache[key] = success;
    return success;
  }
}

DateTime _dateFromEpochSeconds(int? seconds) {
  if (seconds == null || seconds <= 0) return DateTime.now();
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
