import 'package:path/path.dart' as p;
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

import '../constants/app_constants.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'legacy_data_migration.dart';

/// Thin wrapper around the sembast database so tests can open an in-memory
/// instance and production code opens the real file in app-support storage.
class AppDatabase {
  AppDatabase._(this.database, this.path);

  static const AppLogger _log = AppLogger('AppDatabase');
  static bool _storagePrepared = false;

  final Database database;
  final String path;

  /// Prepares persistent storage before preferences are loaded. Windows keys
  /// its support folder from the executable's version metadata, so migrate
  /// legacy data before opening the database or preferences.
  static Future<void> prepareStorage() async {
    if (_storagePrepared) return;

    final directory = await AppStorage.supportDirectory();
    try {
      await LegacyDataMigration.migrate(directory);
    } catch (error, stackTrace) {
      _log.w('Legacy data migration failed; continuing startup', error, stackTrace);
    }
    _storagePrepared = true;
  }

  static Future<AppDatabase> open({String? overridePath}) async {
    final String dbPath;
    if (overridePath != null) {
      dbPath = overridePath;
    } else {
      await prepareStorage();
      final directory = await AppStorage.supportDirectory();
      dbPath = p.join(directory.path, AppConstants.dbFileName);
    }
    _log.d('Opening database at $dbPath');
    final database = await databaseFactoryIo.openDatabase(dbPath);
    return AppDatabase._(database, dbPath);
  }

  static Future<AppDatabase> openInMemory() async {
    final database = await databaseFactoryMemory.openDatabase(
      'nm_vibe_memory.db',
    );
    return AppDatabase._(database, 'memory:nm_vibe_memory.db');
  }

  Future<void> close() => database.close();
}
