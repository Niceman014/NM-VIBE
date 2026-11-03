import 'package:url_launcher/url_launcher.dart';

import '../models/update_manifest.dart';
import 'update_strategy.dart';

class OpenPageStrategy implements UpdateStrategy {
  OpenPageStrategy({required this.platform, Future<bool> Function(Uri)? open})
    : _open =
          open ??
          ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final UpdatePlatform platform;
  final Future<bool> Function(Uri) _open;

  Uri get page => switch (platform) {
    UpdatePlatform.ios || UpdatePlatform.macos => Uri.https(
      'apps.apple.com',
      '/search',
      {'term': 'NM VIBE'},
    ),
    UpdatePlatform.linux || UpdatePlatform.web => Uri.https(
      'github.com',
      '/Niceman014/NM-VIBE/releases',
    ),
    UpdatePlatform.android || UpdatePlatform.windows => throw StateError(
      'This platform has a dedicated update strategy.',
    ),
  };

  @override
  Future<UpdateCheckResult> check({required String currentVersion}) async {
    if (!await _open(page)) {
      throw const UpdateFailure('Could not open the update page.');
    }
    return const UpdateCheckResult(
      status: UpdateStatus.openedPage,
      message: 'Opened the platform update page.',
    );
  }

  @override
  Future<void> install(
    UpdateManifest? manifest, {
    required UpdateProgressCallback onProgress,
  }) async {
    await check(currentVersion: '');
  }

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}

enum UpdatePlatform { android, windows, ios, macos, linux, web }
