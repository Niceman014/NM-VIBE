import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';

/// Copies legacy NM VYBE data into the current support directory before use.
abstract final class LegacyDataMigration {
  static const AppLogger _log = AppLogger('LegacyDataMigration');

  static String? resolveDataDirectoryOverride([
    Map<String, String>? environment,
  ]) {
    final values = environment ?? Platform.environment;
    final current = values['NM_VIBE_DATA_DIR']?.trim();
    if (current != null && current.isNotEmpty) return current;

    final legacy = values['NM_VYBE_DATA_DIR']?.trim();
    return legacy == null || legacy.isEmpty ? null : legacy;
  }

  /// Returns the old Windows and workspace data locations in migration order.
  static Future<List<Directory>> legacyDirectoryCandidates({
    Map<String, String>? environment,
    String? executablePath,
  }) async {
    final values = environment ?? Platform.environment;
    final candidates = <Directory>[];
    final appData = values['APPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) {
      candidates
        ..add(Directory(p.join(appData, 'com.example', 'nm_vybe')))
        ..add(Directory(p.join(appData, 'NM Next', 'NM VYBE')));
    }

    final localAppData = values['LOCALAPPDATA']?.trim();
    if (localAppData != null && localAppData.isNotEmpty) {
      candidates.add(
        Directory(p.join(localAppData, 'NM Next', 'NM VYBE')),
      );
    }

    final workspace = await _workspaceDirectory(
      executablePath ?? Platform.resolvedExecutable,
    );
    if (workspace != null) {
      candidates.add(Directory(p.join(workspace.path, '.nm_vybe_data')));
    }

    final visited = <String>{};
    return candidates.where((candidate) {
      final normalized = p.normalize(candidate.absolute.path).toLowerCase();
      return visited.add(normalized);
    }).toList(growable: false);
  }

  /// Copies legacy folders, migrates the database name, then migrates settings.
  /// Each phase logs and contains its own errors so migration does not abort
  /// normal startup.
  static Future<void> migrate(
    Directory destination, {
    Map<String, String>? environment,
    String? executablePath,
    List<Directory>? legacyDirectories,
    SharedPreferences? preferences,
  }) async {
    var sources = legacyDirectories ?? const <Directory>[];
    try {
      if (legacyDirectories == null) {
        sources = await legacyDirectoryCandidates(
          environment: environment,
          executablePath: executablePath,
        );
      }
      await _copyLegacyFolders(destination, sources);
    } catch (error, stackTrace) {
      _log.w('Could not copy legacy data folders', error, stackTrace);
    }

    try {
      await _migrateDatabase(destination);
    } catch (error, stackTrace) {
      _log.w('Could not migrate the legacy database file', error, stackTrace);
    }

    try {
      await _migrateFallbackPreferences(destination, sources);
    } catch (error, stackTrace) {
      _log.w('Could not migrate fallback preferences', error, stackTrace);
    }

    try {
      final prefs = preferences ?? await SharedPreferences.getInstance();
      await _migratePreferences(prefs);
    } catch (error, stackTrace) {
      _log.w('Could not migrate legacy preferences', error, stackTrace);
    }
  }

  static Future<Directory?> _workspaceDirectory(String executablePath) async {
    var directory = Directory(p.dirname(executablePath)).absolute;
    for (var level = 0; level < 10; level++) {
      if (await File(p.join(directory.path, 'pubspec.yaml')).exists()) {
        return directory;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
    return null;
  }

  static Future<void> _copyLegacyFolders(
    Directory destination,
    Iterable<Directory> sources,
  ) async {
    await destination.create(recursive: true);
    final destinationPath = p.normalize(destination.absolute.path).toLowerCase();
    final newDatabase = File(p.join(destination.path, AppConstants.dbFileName));

    for (final source in sources) {
      final sourcePath = p.normalize(source.absolute.path).toLowerCase();
      if (sourcePath == destinationPath) continue;

      try {
        if (!await source.exists()) continue;
        await for (final entity in source.list(
          recursive: true,
          followLinks: false,
        )) {
          final relativePath = p.relative(entity.path, from: source.path);
          final targetPath = p.join(destination.path, relativePath);
          if (entity is Directory) {
            await Directory(targetPath).create(recursive: true);
            continue;
          }
          if (entity is! File) continue;
          if (p.basename(relativePath) == 'shared_preferences.json') continue;
          if (p.basename(relativePath) == AppConstants.legacyDbFileName &&
              await newDatabase.exists()) {
            continue;
          }
          await _copyFileIfMissing(entity, File(targetPath));
        }
      } catch (error, stackTrace) {
        _log.w('Could not copy legacy folder ${source.path}', error, stackTrace);
      }
    }
  }

  static Future<void> _migrateFallbackPreferences(
    Directory destination,
    Iterable<Directory> sources,
  ) async {
    final destinationPath = p.normalize(destination.absolute.path).toLowerCase();
    final target = File(p.join(destination.path, 'shared_preferences.json'));
    final oldPrefix = 'flutter.${AppConstants.legacyPrefsPrefix}';
    final newPrefix = 'flutter.${AppConstants.prefsPrefix}';

    for (final source in sources) {
      if (p.normalize(source.absolute.path).toLowerCase() == destinationPath) {
        continue;
      }
      final sourceFile = File(p.join(source.path, 'shared_preferences.json'));

      try {
        if (!await sourceFile.exists()) continue;
        final sourceValue = jsonDecode(await sourceFile.readAsString());
        if (sourceValue is! Map) continue;

        final Map<String, Object?> merged;
        if (await target.exists()) {
          final targetValue = jsonDecode(await target.readAsString());
          if (targetValue is! Map) {
            _log.w(
              'Could not migrate fallback preferences: destination is not a map',
            );
            continue;
          }
          merged = Map<String, Object?>.from(targetValue);
        } else {
          merged = <String, Object?>{};
        }

        var changed = false;
        for (final entry in sourceValue.entries) {
          final oldKey = entry.key;
          if (oldKey is! String || !oldKey.startsWith(oldPrefix)) continue;
          final newKey = '$newPrefix${oldKey.substring(oldPrefix.length)}';
          if (merged.containsKey(newKey)) continue;
          merged[newKey] = entry.value;
          merged.remove(oldKey);
          changed = true;
        }
        if (!changed) continue;

        await _writeFallbackPreferences(target, merged);
      } catch (error, stackTrace) {
        _log.w(
          'Could not migrate fallback preferences from ${source.path}',
          error,
          stackTrace,
        );
      }
    }
  }

  static Future<void> _writeFallbackPreferences(
    File target,
    Map<String, Object?> values,
  ) async {
    await target.parent.create(recursive: true);
    final temporary = File(
      '${target.path}.migration_${DateTime.now().microsecondsSinceEpoch}',
    );
    File? backup;
    final targetOriginallyExisted = await target.exists();
    var replacementInstalled = false;
    try {
      await temporary.writeAsString(jsonEncode(values), flush: true);
      final confirmation = jsonDecode(await temporary.readAsString());
      if (confirmation is! Map) {
        throw const FormatException('Fallback preferences copy is not a map');
      }
      for (final entry in values.entries) {
        if (jsonEncode(confirmation[entry.key]) != jsonEncode(entry.value)) {
          throw FileSystemException(
            'Fallback preferences copy was not confirmed',
            temporary.path,
          );
        }
      }

      if (targetOriginallyExisted) {
        backup = File(
          '${target.path}.migration_backup_${DateTime.now().microsecondsSinceEpoch}',
        );
        await target.rename(backup.path);
      }
      await temporary.rename(target.path);
      replacementInstalled = true;

      final saved = jsonDecode(await target.readAsString());
      if (saved is! Map ||
          values.entries.any(
            (entry) => jsonEncode(saved[entry.key]) != jsonEncode(entry.value),
          )) {
        throw FileSystemException(
          'Fallback preferences update was not confirmed',
          target.path,
        );
      }
      if (backup != null && await backup.exists()) await backup.delete();
    } on Object {
      if (backup != null && await backup.exists()) {
        if (await target.exists()) await target.delete();
        await backup.rename(target.path);
      } else if (!targetOriginallyExisted &&
          replacementInstalled &&
          await target.exists()) {
        await target.delete();
      }
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  static Future<void> _copyFileIfMissing(File source, File target) async {
    await target.parent.create(recursive: true);
    RandomAccessFile? output;
    var created = false;
    try {
      await target.create(exclusive: true);
      created = true;
      output = await target.open(mode: FileMode.write);
      await for (final chunk in source.openRead()) {
        await output.writeFrom(chunk);
      }
      await output.flush();
      await output.close();
      output = null;

      if (!await target.exists() ||
          await target.length() != await source.length()) {
        throw FileSystemException(
          'Legacy file copy was not confirmed',
          target.path,
        );
      }
    } on FileSystemException catch (error, stackTrace) {
      if (output != null) await output.close();
      if (created && await target.exists()) await target.delete();
      if (created || !await target.exists()) {
        _log.w('Could not copy legacy file ${source.path}', error, stackTrace);
      }
      // An already-existing destination is intentionally preserved.
    } catch (error, stackTrace) {
      if (output != null) await output.close();
      if (created && await target.exists()) await target.delete();
      _log.w('Could not copy legacy file ${source.path}', error, stackTrace);
    }
  }

  static Future<void> _migrateDatabase(Directory directory) async {
    final current = File(p.join(directory.path, AppConstants.dbFileName));
    if (await current.exists()) return;

    final legacy = File(p.join(directory.path, AppConstants.legacyDbFileName));
    if (!await legacy.exists()) return;

    await legacy.rename(current.path);
    if (!await current.exists()) {
      throw FileSystemException(
        'Database rename was not confirmed',
        current.path,
      );
    }
  }

  static Future<void> _migratePreferences(SharedPreferences preferences) async {
    final keys = preferences.getKeys()
        .where((key) => key.startsWith(AppConstants.legacyPrefsPrefix))
        .toList(growable: false);

    for (final oldKey in keys) {
      try {
        final newKey = AppConstants.prefsPrefix +
            oldKey.substring(AppConstants.legacyPrefsPrefix.length);
        if (preferences.containsKey(newKey)) continue;

        final oldValue = preferences.get(oldKey);
        if (oldValue == null) continue;
        final written = await _writePreference(preferences, newKey, oldValue);
        if (!written || !_samePreference(preferences.get(newKey), oldValue)) {
          continue;
        }
        await preferences.remove(oldKey);
      } catch (error, stackTrace) {
        _log.w('Could not migrate preference $oldKey', error, stackTrace);
      }
    }
  }

  static Future<bool> _writePreference(
    SharedPreferences preferences,
    String key,
    Object value,
  ) {
    if (value is bool) return preferences.setBool(key, value);
    if (value is int) return preferences.setInt(key, value);
    if (value is double) return preferences.setDouble(key, value);
    if (value is String) return preferences.setString(key, value);
    if (value is List<String>) return preferences.setStringList(key, value);
    return Future<bool>.value(false);
  }

  static bool _samePreference(Object? first, Object? second) {
    if (first is List<String> && second is List<String>) {
      if (first.length != second.length) return false;
      for (var index = 0; index < first.length; index++) {
        if (first[index] != second[index]) return false;
      }
      return true;
    }
    return first == second;
  }
}
