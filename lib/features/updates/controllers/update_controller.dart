import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:nm_vibe/core/constants/app_constants.dart';
import 'package:nm_vibe/core/storage/settings_service.dart';
import '../models/update_manifest.dart';
import '../services/update_strategy.dart';

@immutable
class UpdateUiState {
  const UpdateUiState({
    this.status = UpdateStatus.idle,
    this.currentVersion,
    this.manifest,
    this.requiresUpdate = false,
    this.progress,
    this.message,
  });

  final UpdateStatus status;
  final String? currentVersion;
  final UpdateManifest? manifest;
  final bool requiresUpdate;
  final double? progress;
  final String? message;
}

class UpdateController extends StateNotifier<UpdateUiState> {
  UpdateController(this._strategy) : super(const UpdateUiState());

  static const _lastAutomaticCheckKey =
      '${AppConstants.prefsPrefix}lastAutomaticUpdateCheck';

  final UpdateStrategy _strategy;

  Future<void> checkForUpdates({bool automatic = false}) async {
    if (state.status == UpdateStatus.checking ||
        state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.verifying) {
      return;
    }
    if (automatic && !await _claimAutomaticCheck()) return;
    final previous = state;
    state = UpdateUiState(
      status: UpdateStatus.checking,
      currentVersion: previous.currentVersion,
      manifest: previous.manifest,
      requiresUpdate: previous.requiresUpdate,
    );
    try {
      final package = await PackageInfo.fromPlatform();
      final result = await _strategy.check(currentVersion: package.version);
      state = UpdateUiState(
        status: result.status,
        currentVersion: package.version,
        manifest: result.manifest,
        requiresUpdate: result.requiresUpdate,
        message: result.message,
      );
    } on UpdateFailure catch (error) {
      state = UpdateUiState(
        status: UpdateStatus.failed,
        currentVersion: state.currentVersion,
        manifest: previous.manifest,
        requiresUpdate: previous.requiresUpdate,
        message: error.message,
      );
    } catch (_) {
      state = UpdateUiState(
        status: UpdateStatus.failed,
        currentVersion: state.currentVersion,
        manifest: previous.manifest,
        requiresUpdate: previous.requiresUpdate,
        message: 'Could not check for updates. Please try again.',
      );
    }
  }

  Future<bool> _claimAutomaticCheck() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) return false;
      final preferences = await AppPreferences.open();
      final now = DateTime.now();
      final today =
          '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      if (preferences.getString(_lastAutomaticCheckKey) == today) return false;
      await preferences.setString(_lastAutomaticCheckKey, today);
      return true;
    } catch (_) {
      // An optional background check must never prevent the app from starting.
      return false;
    }
  }

  Future<void> installAvailable() async {
    final manifest = state.manifest;
    if (state.status != UpdateStatus.available) return;
    if (manifest != null && !manifest.downloadConfigured) {
      state = UpdateUiState(
        status: UpdateStatus.failed,
        currentVersion: state.currentVersion,
        manifest: manifest,
        requiresUpdate: state.requiresUpdate,
        message: 'Installer hosting is not configured yet.',
      );
      return;
    }
    state = UpdateUiState(
      status: UpdateStatus.downloading,
      currentVersion: state.currentVersion,
      manifest: manifest,
      requiresUpdate: state.requiresUpdate,
      progress: 0,
    );
    try {
      await _strategy.install(
        manifest,
        onProgress: (status, progress) {
          state = UpdateUiState(
            status: status,
            currentVersion: state.currentVersion,
            manifest: manifest,
            requiresUpdate: state.requiresUpdate,
            progress: progress,
          );
        },
      );
      if (state.status != UpdateStatus.launched) {
        state = UpdateUiState(
          status: UpdateStatus.launched,
          currentVersion: state.currentVersion,
          manifest: manifest,
          message: 'Google Play is handling the update.',
        );
      }
    } on UpdateCancelled {
      state = UpdateUiState(
        status: UpdateStatus.cancelled,
        currentVersion: state.currentVersion,
        manifest: manifest,
        requiresUpdate: state.requiresUpdate,
        message: 'Update download cancelled.',
      );
    } on UpdateFailure catch (error) {
      state = UpdateUiState(
        status: UpdateStatus.failed,
        currentVersion: state.currentVersion,
        manifest: manifest,
        requiresUpdate: state.requiresUpdate,
        message: error.message,
      );
    } catch (_) {
      state = UpdateUiState(
        status: UpdateStatus.failed,
        currentVersion: state.currentVersion,
        manifest: manifest,
        requiresUpdate: state.requiresUpdate,
        message: 'The update could not be completed. Please retry.',
      );
    }
  }

  Future<void> cancelDownload() => _strategy.cancel();

  @override
  void dispose() {
    _strategy.dispose();
    super.dispose();
  }
}
