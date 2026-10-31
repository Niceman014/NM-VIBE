import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/logger.dart';
import 'legacy_data_migration.dart';

/// Resolves the writable per-user data directory used by NM VIBE.
///
/// The environment override supports portable and restricted development
/// environments. Windows normally uses the app's roaming support folder; if
/// that folder is unavailable, fall back to the local app-data folder.
abstract final class AppStorage {
  static const AppLogger _log = AppLogger('AppStorage');
  static bool _loggedWorkspaceFallback = false;

  static Future<Directory> supportDirectory() async {
    final candidates = <Directory>[];
    final failures = <String>[];
    String? workspaceFallbackPath;

    final override = LegacyDataMigration.resolveDataDirectoryOverride();
    if (override != null && override.isNotEmpty) {
      candidates.add(Directory(override));
    }

    try {
      candidates.add(await getApplicationSupportDirectory());
    } catch (error) {
      failures.add('Application support directory: $error');
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA']?.trim();
      if (localAppData != null && localAppData.isNotEmpty) {
        candidates.add(Directory(p.join(localAppData, 'NM Next', 'NM VIBE')));
      }

      final workspaceData = kDebugMode ? await _workspaceDataDirectory() : null;
      if (workspaceData != null) {
        workspaceFallbackPath = p
            .normalize(workspaceData.absolute.path)
            .toLowerCase();
        candidates.add(workspaceData);
      }
    }

    final visited = <String>{};
    for (final candidate in candidates) {
      final normalizedPath = p.normalize(candidate.absolute.path);
      if (!visited.add(normalizedPath.toLowerCase())) continue;
      try {
        await _verifyWritable(candidate);
        if (workspaceFallbackPath != null &&
            normalizedPath.toLowerCase() == workspaceFallbackPath &&
            !_loggedWorkspaceFallback) {
          _loggedWorkspaceFallback = true;
          _log.w(
            'Windows AppData is unavailable. Using the project-local '
            'development data folder at $normalizedPath; installed builds do '
            'not use this fallback.',
          );
        }
        return candidate;
      } catch (error) {
        failures.add('$normalizedPath: $error');
      }
    }

    throw FileSystemException(
      'NM VIBE could not find a writable data folder. Check folder access, '
      'or launch the development build from the project.',
      failures.join(' | '),
    );
  }

  static Future<Directory?> _workspaceDataDirectory() async {
    var directory = Directory(p.dirname(Platform.resolvedExecutable)).absolute;
    for (var level = 0; level < 10; level++) {
      if (await File(p.join(directory.path, 'pubspec.yaml')).exists()) {
        return Directory(p.join(directory.path, '.nm_vibe_data'));
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return null;
  }

  static Future<void> _verifyWritable(Directory directory) async {
    await directory.create(recursive: true);
    final probe = File(
      p.join(
        directory.path,
        '.nm_vibe_write_check_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await probe.writeAsBytes(const <int>[0], flush: true);
    await probe.delete();
  }
}
