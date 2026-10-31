import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/core/constants/app_constants.dart';
import 'package:nm_vibe/core/storage/legacy_data_migration.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Future<Directory> _temporaryDirectory() async {
  final directory = await Directory.systemTemp.createTemp('nm_vibe_migration_');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  return directory;
}

Future<SharedPreferences> _preferences([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LegacyDataMigration', () {
    test('copies all legacy data folder candidates', () async {
      final root = await _temporaryDirectory();
      final appData = p.join(root.path, 'roaming');
      final localAppData = p.join(root.path, 'local');
      final workspace = Directory(p.join(root.path, 'workspace'));
      await workspace.create(recursive: true);
      await File(
        p.join(workspace.path, 'pubspec.yaml'),
      ).writeAsString('name: test');
      final executablePath = p.join(
        workspace.path,
        'build',
        'windows',
        'runner',
        'Debug',
        'nm_vibe.exe',
      );
      final environment = <String, String>{
        'APPDATA': appData,
        'LOCALAPPDATA': localAppData,
      };
      final sources = await LegacyDataMigration.legacyDirectoryCandidates(
        environment: environment,
        executablePath: executablePath,
      );
      expect(
        sources.map((source) => p.normalize(source.path)).toList(),
        [
          p.join(appData, 'com.example', 'nm_vybe'),
          p.join(appData, 'NM Next', 'NM VYBE'),
          p.join(localAppData, 'NM Next', 'NM VYBE'),
          p.join(workspace.path, '.nm_vybe_data'),
        ].map(p.normalize).toList(),
      );

      for (var index = 0; index < sources.length; index++) {
        final marker = File(p.join(sources[index].path, 'folder_$index.txt'));
        await marker.parent.create(recursive: true);
        await marker.writeAsString('legacy-$index');
      }

      final destination = Directory(p.join(root.path, 'support'));
      final preferences = await _preferences();
      await LegacyDataMigration.migrate(
        destination,
        environment: environment,
        executablePath: executablePath,
        preferences: preferences,
      );

      for (var index = 0; index < sources.length; index++) {
        expect(
          await File(
            p.join(destination.path, 'folder_$index.txt'),
          ).readAsString(),
          'legacy-$index',
        );
      }
    });

    test(
      'renames the legacy database only when the current one is absent',
      () async {
        final root = await _temporaryDirectory();
        final destination = Directory(p.join(root.path, 'support'));
        await destination.create(recursive: true);
        final oldDatabase = File(
          p.join(destination.path, AppConstants.legacyDbFileName),
        );
        await oldDatabase.writeAsBytes(const [1, 2, 3]);
        final preferences = await _preferences();

        await LegacyDataMigration.migrate(
          destination,
          legacyDirectories: const [],
          preferences: preferences,
        );

        expect(
          await File(
            p.join(destination.path, AppConstants.dbFileName),
          ).readAsBytes(),
          const [1, 2, 3],
        );
        expect(await oldDatabase.exists(), isFalse);
      },
    );

    test('copies prefixed keys then removes their legacy keys', () async {
      final root = await _temporaryDirectory();
      final destination = Directory(p.join(root.path, 'support'));
      final legacyFolder = Directory(p.join(root.path, 'legacy'));
      final legacyFallback = File(
        p.join(legacyFolder.path, 'shared_preferences.json'),
      );
      await legacyFallback.parent.create(recursive: true);
      await legacyFallback.writeAsString(
        jsonEncode({
          'flutter.nm_vybe.cached': 'restored',
          'flutter.nm_vybe.keep': 'old',
        }),
      );
      await destination.create(recursive: true);
      await File(p.join(destination.path, 'shared_preferences.json'))
          .writeAsString(
            jsonEncode({
              'flutter.nm_vibe.keep': 'current',
              'other': 'preserved',
            }),
          );
      final preferences = await _preferences({
        'nm_vybe.themeMode': 'dark',
        'nm_vybe.libraryFolders': <String>['Music', 'Archive'],
      });

      await LegacyDataMigration.migrate(
        destination,
        legacyDirectories: [legacyFolder],
        preferences: preferences,
      );

      expect(preferences.getString('nm_vibe.themeMode'), 'dark');
      expect(
        preferences.getStringList('nm_vibe.libraryFolders'),
        ['Music', 'Archive'],
      );
      expect(preferences.containsKey('nm_vybe.themeMode'), isFalse);
      expect(preferences.containsKey('nm_vybe.libraryFolders'), isFalse);
      final migratedFallback = jsonDecode(
        await File(p.join(destination.path, 'shared_preferences.json'))
            .readAsString(),
      ) as Map<String, dynamic>;
      expect(migratedFallback['flutter.nm_vibe.cached'], 'restored');
      expect(migratedFallback['flutter.nm_vibe.keep'], 'current');
      expect(migratedFallback['other'], 'preserved');
      final originalFallback =
          jsonDecode(await legacyFallback.readAsString()) as Map<String, dynamic>;
      expect(originalFallback['flutter.nm_vybe.cached'], 'restored');
    });

    test(
      'prefers the new environment variable and falls back to the old one',
      () async {
        final root = await _temporaryDirectory();
        final oldPath = p.join(root.path, 'old');
        final newPath = p.join(root.path, 'new');

        expect(
          LegacyDataMigration.resolveDataDirectoryOverride({
            'NM_VYBE_DATA_DIR': oldPath,
          }),
          oldPath,
        );
        expect(
          LegacyDataMigration.resolveDataDirectoryOverride({
            'NM_VIBE_DATA_DIR': newPath,
            'NM_VYBE_DATA_DIR': oldPath,
          }),
          newPath,
        );
      },
    );

    test('can run twice without losing migrated data', () async {
      final root = await _temporaryDirectory();
      final source = Directory(p.join(root.path, 'legacy'));
      final destination = Directory(p.join(root.path, 'support'));
      final oldDatabase = File(
        p.join(source.path, AppConstants.legacyDbFileName),
      );
      await oldDatabase.parent.create(recursive: true);
      await oldDatabase.writeAsString('database');
      final audioFile = File(p.join(source.path, 'album', 'track.dat'));
      await audioFile.parent.create(recursive: true);
      await audioFile.writeAsString('audio');
      final preferences = await _preferences({'nm_vybe.volume': 8});

      for (var attempt = 0; attempt < 2; attempt++) {
        await LegacyDataMigration.migrate(
          destination,
          legacyDirectories: [source],
          preferences: preferences,
        );
      }

      expect(
        await File(p.join(destination.path, AppConstants.dbFileName))
            .readAsString(),
        'database',
      );
      expect(
        await File(
          p.join(destination.path, AppConstants.legacyDbFileName),
        ).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(destination.path, 'album', 'track.dat'),
        ).readAsString(),
        'audio',
      );
      expect(preferences.getInt('nm_vibe.volume'), 8);
      expect(preferences.containsKey('nm_vybe.volume'), isFalse);
    });

    test('never overwrites existing destination data', () async {
      final root = await _temporaryDirectory();
      final source = Directory(p.join(root.path, 'legacy'));
      final destination = Directory(p.join(root.path, 'support'));
      final sourceAudio = File(p.join(source.path, 'music', 'track.dat'));
      await sourceAudio.parent.create(recursive: true);
      await sourceAudio.writeAsString('old audio');
      final destinationAudio = File(
        p.join(destination.path, 'music', 'track.dat'),
      );
      await destinationAudio.parent.create(recursive: true);
      await destinationAudio.writeAsString('new audio');
      final currentDatabase = File(
        p.join(destination.path, AppConstants.dbFileName),
      );
      await currentDatabase.parent.create(recursive: true);
      await currentDatabase.writeAsString('new database');
      final oldDatabase = File(
        p.join(destination.path, AppConstants.legacyDbFileName),
      );
      await oldDatabase.writeAsString('old database');
      final preferences = await _preferences({
        'nm_vybe.volume': 3,
        'nm_vibe.volume': 9,
      });

      await LegacyDataMigration.migrate(
        destination,
        legacyDirectories: [source],
        preferences: preferences,
      );

      expect(await destinationAudio.readAsString(), 'new audio');
      expect(await currentDatabase.readAsString(), 'new database');
      expect(await oldDatabase.readAsString(), 'old database');
      expect(preferences.getInt('nm_vibe.volume'), 9);
      expect(preferences.getInt('nm_vybe.volume'), 3);
    });
  });
}
