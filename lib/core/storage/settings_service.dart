import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';
import '../constants/theme_constants.dart';
import '../utils/logger.dart';
import 'app_storage.dart';
import 'db_service.dart';

/// Shared app preferences with a file-backed Windows fallback.
///
/// The fallback is used when Windows denies the roaming profile folder. It
/// stores the same Flutter-prefixed keys beside the app database, preserving
/// existing SharedPreferences values when the legacy file was migrated.
class AppPreferences {
  AppPreferences._({
    this._sharedPreferences,
    Map<String, Object?> values = const <String, Object?>{},
    this._file,
  }) : _values = Map<String, Object?>.of(values);

  static const AppLogger _log = AppLogger('AppPreferences');
  static const String _pluginPrefix = 'flutter.';

  final SharedPreferences? _sharedPreferences;
  final Map<String, Object?> _values;
  final File? _file;
  Future<void> _pendingWrite = Future<void>.value();

  static Future<AppPreferences> open() async {
    await AppDatabase.prepareStorage();
    try {
      return AppPreferences._(
        sharedPreferences: await SharedPreferences.getInstance(),
      );
    } catch (error, stackTrace) {
      if (!Platform.isWindows) rethrow;
      _log.w(
        'Windows preferences unavailable; using local app storage',
        error,
        stackTrace,
      );
    }

    final directory = await AppStorage.supportDirectory();
    final file = File(p.join(directory.path, 'shared_preferences.json'));
    Map<String, Object?> values = <String, Object?>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) values = Map<String, Object?>.from(decoded);
      } catch (error, stackTrace) {
        final backup = File(
          '${file.path}.corrupt_${DateTime.now().millisecondsSinceEpoch}',
        );
        try {
          await file.rename(backup.path);
          _log.w(
            'Moved invalid preferences aside to ${backup.path}',
            error,
            stackTrace,
          );
        } catch (renameError, renameStackTrace) {
          _log.w(
            'Could not recover invalid preferences',
            renameError,
            renameStackTrace,
          );
        }
      }
    }
    return AppPreferences._(values: values, file: file);
  }

  String _key(String key) => '$_pluginPrefix$key';

  String? getString(String key) {
    final value = _sharedPreferences?.getString(key) ?? _values[_key(key)];
    return value is String ? value : null;
  }

  bool? getBool(String key) {
    final value = _sharedPreferences?.getBool(key) ?? _values[_key(key)];
    return value is bool ? value : null;
  }

  int? getInt(String key) {
    final value = _sharedPreferences?.getInt(key) ?? _values[_key(key)];
    return value is int ? value : null;
  }

  List<String>? getStringList(String key) {
    final value = _sharedPreferences?.getStringList(key) ?? _values[_key(key)];
    if (value is! List || value.any((item) => item is! String)) return null;
    return value.cast<String>();
  }

  Future<bool> setString(String key, String value) =>
      _set(key, value, (prefs) => prefs.setString(key, value));

  Future<bool> setBool(String key, bool value) =>
      _set(key, value, (prefs) => prefs.setBool(key, value));

  Future<bool> setInt(String key, int value) =>
      _set(key, value, (prefs) => prefs.setInt(key, value));

  Future<bool> setStringList(String key, List<String> value) => _set(
    key,
    List<String>.of(value),
    (prefs) => prefs.setStringList(key, value),
  );

  Future<bool> _set(
    String key,
    Object value,
    Future<bool> Function(SharedPreferences) sharedSetter,
  ) async {
    final shared = _sharedPreferences;
    if (shared != null) return sharedSetter(shared);

    _values[_key(key)] = value;
    final file = _file;
    if (file == null) return false;
    final encoded = jsonEncode(_values);
    _pendingWrite = _pendingWrite.then((_) async {
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
    });
    await _pendingWrite;
    return true;
  }
}

/// How the song list is ordered on the Library screen.
enum SongsSortMode {
  title('Title'),
  artist('Artist'),
  album('Album'),
  dateAdded('Date added'),
  duration('Duration');

  const SongsSortMode(this.label);
  final String label;
}

/// Everything the user can tweak. Persisted using [AppPreferences].
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = false,
    this.usePureBlackTheme = false,
    this.seedColorValue = ThemeConstants.defaultSeedValue,
    this.libraryFolders = const <String>[],
    this.songsSortMode = SongsSortMode.title,
    this.songsSortAscending = true,
    this.autoScanOnStartup = true,
    this.showLyricsInPlayer = true,
    this.onboardingComplete = false,
    this.wifiOnlyDownloads = false,
    this.downloadStorageLimitMb = 1024,
  });

  final ThemeMode themeMode;

  /// Use the Android 12+ system wallpaper palette when available.
  final bool useDynamicColor;
  final bool usePureBlackTheme;
  final int seedColorValue;

  /// Desktop folders to scan. Empty means "detect the default music folder".
  final List<String> libraryFolders;

  final SongsSortMode songsSortMode;
  final bool songsSortAscending;
  final bool autoScanOnStartup;
  final bool showLyricsInPlayer;
  final bool onboardingComplete;
  final bool wifiOnlyDownloads;
  final int downloadStorageLimitMb;

  Color get seedColor => Color(seedColorValue);

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? useDynamicColor,
    bool? usePureBlackTheme,
    int? seedColorValue,
    List<String>? libraryFolders,
    SongsSortMode? songsSortMode,
    bool? songsSortAscending,
    bool? autoScanOnStartup,
    bool? showLyricsInPlayer,
    bool? onboardingComplete,
    bool? wifiOnlyDownloads,
    int? downloadStorageLimitMb,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      usePureBlackTheme: usePureBlackTheme ?? this.usePureBlackTheme,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      libraryFolders: libraryFolders ?? this.libraryFolders,
      songsSortMode: songsSortMode ?? this.songsSortMode,
      songsSortAscending: songsSortAscending ?? this.songsSortAscending,
      autoScanOnStartup: autoScanOnStartup ?? this.autoScanOnStartup,
      showLyricsInPlayer: showLyricsInPlayer ?? this.showLyricsInPlayer,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      wifiOnlyDownloads: wifiOnlyDownloads ?? this.wifiOnlyDownloads,
      downloadStorageLimitMb: downloadStorageLimitMb ?? this.downloadStorageLimitMb,
    );
  }
}

/// Reads/writes [AppSettings] and exposes them as Riverpod state.
class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._prefs) : super(_read(_prefs));

  final AppPreferences _prefs;

  static const String _themeModeKey = '${AppConstants.prefsPrefix}themeMode';
  static const String _dynamicColorKey =
      '${AppConstants.prefsPrefix}useDynamicColor';
  static const String _pureBlackKey =
      '${AppConstants.prefsPrefix}usePureBlackTheme';
  static const String _seedColorKey = '${AppConstants.prefsPrefix}seedColor';
  static const String _libraryFoldersKey =
      '${AppConstants.prefsPrefix}libraryFolders';
  static const String _sortModeKey = '${AppConstants.prefsPrefix}songsSortMode';
  static const String _sortAscendingKey =
      '${AppConstants.prefsPrefix}songsSortAscending';
  static const String _autoScanKey = '${AppConstants.prefsPrefix}autoScan';
  static const String _showLyricsKey = '${AppConstants.prefsPrefix}showLyrics';
  static const String _onboardingKey =
      '${AppConstants.prefsPrefix}onboardingComplete';
  static const String _wifiOnlyDownloadsKey =
      '${AppConstants.prefsPrefix}wifiOnlyDownloads';
  static const String _downloadStorageLimitMbKey =
      '${AppConstants.prefsPrefix}downloadStorageLimitMb';

  static AppSettings _read(AppPreferences prefs) {
    final themeModeName = prefs.getString(_themeModeKey);
    final sortModeName = prefs.getString(_sortModeKey);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == themeModeName,
        orElse: () => ThemeMode.system,
      ),
      useDynamicColor: prefs.getBool(_dynamicColorKey) ?? false,
      usePureBlackTheme: prefs.getBool(_pureBlackKey) ?? false,
      seedColorValue:
          prefs.getInt(_seedColorKey) ?? ThemeConstants.defaultSeedValue,
      libraryFolders: prefs.getStringList(_libraryFoldersKey) ?? const [],
      songsSortMode: SongsSortMode.values.firstWhere(
        (mode) => mode.name == sortModeName,
        orElse: () => SongsSortMode.title,
      ),
      songsSortAscending: prefs.getBool(_sortAscendingKey) ?? true,
      autoScanOnStartup: prefs.getBool(_autoScanKey) ?? true,
      showLyricsInPlayer: prefs.getBool(_showLyricsKey) ?? true,
      onboardingComplete: prefs.getBool(_onboardingKey) ?? false,
      wifiOnlyDownloads: prefs.getBool(_wifiOnlyDownloadsKey) ?? false,
      downloadStorageLimitMb: prefs.getInt(_downloadStorageLimitMbKey) ?? 1024,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_themeModeKey, mode.name);
  }

  Future<void> setUseDynamicColor(bool enabled) async {
    state = state.copyWith(useDynamicColor: enabled);
    await _prefs.setBool(_dynamicColorKey, enabled);
  }

  Future<void> setUsePureBlackTheme(bool enabled) async {
    state = state.copyWith(usePureBlackTheme: enabled);
    await _prefs.setBool(_pureBlackKey, enabled);
  }

  Future<void> setSeedColorValue(int value) async {
    state = state.copyWith(seedColorValue: value);
    await _prefs.setInt(_seedColorKey, value);
  }

  Future<void> setLibraryFolders(List<String> folders) async {
    state = state.copyWith(libraryFolders: folders);
    await _prefs.setStringList(_libraryFoldersKey, folders);
  }

  Future<void> setSongsSortMode(SongsSortMode mode) async {
    state = state.copyWith(songsSortMode: mode);
    await _prefs.setString(_sortModeKey, mode.name);
  }

  Future<void> setSongsSortAscending(bool ascending) async {
    state = state.copyWith(songsSortAscending: ascending);
    await _prefs.setBool(_sortAscendingKey, ascending);
  }

  Future<void> setAutoScanOnStartup(bool enabled) async {
    state = state.copyWith(autoScanOnStartup: enabled);
    await _prefs.setBool(_autoScanKey, enabled);
  }

  Future<void> setShowLyricsInPlayer(bool enabled) async {
    state = state.copyWith(showLyricsInPlayer: enabled);
    await _prefs.setBool(_showLyricsKey, enabled);
  }

  Future<void> completeOnboarding() async {
    state = state.copyWith(onboardingComplete: true);
    await _prefs.setBool(_onboardingKey, true);
  }

  Future<void> setWifiOnlyDownloads(bool enabled) async {
    state = state.copyWith(wifiOnlyDownloads: enabled);
    await _prefs.setBool(_wifiOnlyDownloadsKey, enabled);
  }

  Future<void> setDownloadStorageLimitMb(int megabytes) async {
    state = state.copyWith(downloadStorageLimitMb: megabytes);
    await _prefs.setInt(_downloadStorageLimitMbKey, megabytes);
  }
}
