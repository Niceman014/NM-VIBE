import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../utils/logger.dart';
import '../storage/app_storage.dart';

/// Stores album artwork extracted during scanning as small files in
/// app-support storage. Songs reference artwork by [Song.artworkKey], never by
/// absolute path, so the cache can be relocated or rebuilt safely.
class ArtworkService {
  ArtworkService();

  static const AppLogger _log = AppLogger('Artwork');

  Directory? _cacheDirectory;
  final Map<String, File?> _resolved = <String, File?>{};

  static const List<String> _extensions = ['.jpg', '.jpeg', '.png', '.webp'];

  Future<Directory> _directory() async {
    final existing = _cacheDirectory;
    if (existing != null) return existing;
    final support = await AppStorage.supportDirectory();
    final directory = Directory(
      p.join(support.path, AppConstants.artworkDirName),
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _cacheDirectory = directory;
    return directory;
  }

  /// Returns the cached artwork file for [key], if it exists.
  Future<File?> fileForKey(String? key) async {
    if (key == null || key.isEmpty) return null;
    if (_resolved.containsKey(key)) return _resolved[key];
    final directory = await _directory();
    for (final extension in _extensions) {
      final file = File(p.join(directory.path, '$key$extension'));
      if (await file.exists()) {
        _resolved[key] = file;
        return file;
      }
    }
    _resolved[key] = null;
    return null;
  }

  /// Writes [bytes] to the cache and returns the artwork key.
  Future<String?> cacheArtwork(String key, Uint8List bytes) async {
    if (bytes.isEmpty || key.isEmpty) return null;
    try {
      final directory = await _directory();
      final extension = _extensionFor(bytes);
      final file = File(p.join(directory.path, '$key$extension'));
      await file.writeAsBytes(bytes, flush: true);
      _resolved[key] = file;
      return key;
    } catch (error, stackTrace) {
      _log.w('Could not cache artwork for $key', error, stackTrace);
      return null;
    }
  }

  /// Deletes every cached artwork file (used by "clear library" / reset).
  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
      await directory.create(recursive: true);
    }
    _resolved.clear();
  }

  /// Removes cached files whose keys are not in [keepKeys].
  Future<void> prune(Set<String> keepKeys) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (!keepKeys.contains(name)) {
        try {
          await entity.delete();
          _resolved.remove(name);
        } catch (_) {
          // Best effort cleanup.
        }
      }
    }
  }

  /// Total size of the artwork cache in bytes.
  Future<int> sizeBytes() async {
    final directory = await _directory();
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Ignore unreadable entries.
        }
      }
    }
    return total;
  }

  static String _extensionFor(Uint8List bytes) {
    if (bytes.length > 4) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) return '.jpg';
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E) {
        return '.png';
      }
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46) {
        return '.webp';
      }
    }
    return '.jpg';
  }
}

final artworkServiceProvider = Provider<ArtworkService>((ref) {
  return ArtworkService();
});

/// Async resolution of a cached artwork file for a widget.
final artworkFileProvider = FutureProvider.family<File?, String?>((ref, key) {
  return ref.watch(artworkServiceProvider).fileForKey(key);
});
