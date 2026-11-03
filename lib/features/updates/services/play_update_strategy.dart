import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/update_manifest.dart';
import 'update_strategy.dart';

class PlayUpdateStrategy implements UpdateStrategy {
  PlayUpdateStrategy({
    Future<AppUpdateInfo> Function()? checkForUpdate,
    Future<AppUpdateResult> Function()? performImmediateUpdate,
    Future<String> Function()? packageName,
    Future<bool> Function(Uri)? open,
  }) : _checkForUpdate = checkForUpdate ?? InAppUpdate.checkForUpdate,
       _performImmediateUpdate =
           performImmediateUpdate ?? InAppUpdate.performImmediateUpdate,
       _packageName = packageName ?? _readPackageName,
       _open =
           open ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final Future<AppUpdateInfo> Function() _checkForUpdate;
  final Future<AppUpdateResult> Function() _performImmediateUpdate;
  final Future<String> Function() _packageName;
  final Future<bool> Function(Uri) _open;

  Future<Uri> _listingUri() async => Uri.https(
    'play.google.com',
    '/store/apps/details',
    {'id': await _packageName()},
  );

  @override
  Future<UpdateCheckResult> check({required String currentVersion}) async {
    try {
      final info = await _checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress) {
        return const UpdateCheckResult(status: UpdateStatus.available);
      }
      return const UpdateCheckResult(status: UpdateStatus.upToDate);
    } on PlatformException {
      return _openStoreFallback();
    } catch (_) {
      // Sideloaded and development builds cannot use Play's update API.
      return _openStoreFallback();
    }
  }

  Future<UpdateCheckResult> _openStoreFallback() async {
    final opened = await _open(await _listingUri());
    if (!opened) throw const UpdateFailure('Could not open Google Play.');
    return const UpdateCheckResult(
      status: UpdateStatus.openedPage,
      message: 'Google Play manages updates for this app.',
    );
  }

  @override
  Future<void> install(
    UpdateManifest? manifest, {
    required UpdateProgressCallback onProgress,
  }) async {
    try {
      final result = await _performImmediateUpdate();
      if (result == AppUpdateResult.userDeniedUpdate) {
        throw const UpdateCancelled();
      }
      if (result == AppUpdateResult.inAppUpdateFailed) {
        final opened = await _open(await _listingUri());
        if (!opened) {
          throw const UpdateFailure('Google Play could not start the update.');
        }
      }
    } on UpdateCancelled {
      rethrow;
    } on PlatformException {
      final opened = await _open(await _listingUri());
      if (!opened) {
        throw const UpdateFailure('Google Play could not start the update.');
      }
    } catch (_) {
      final opened = await _open(await _listingUri());
      if (!opened) {
        throw const UpdateFailure('Google Play could not start the update.');
      }
    }
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

  static Future<String> _readPackageName() async =>
      (await PackageInfo.fromPlatform()).packageName;
}
