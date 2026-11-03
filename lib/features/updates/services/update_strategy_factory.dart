import 'dart:io';

import 'package:flutter/foundation.dart';

import 'open_page_strategy.dart';
import 'play_update_strategy.dart';
import 'update_strategy.dart';
import 'windows_installer_strategy.dart';

class UpdateStrategyFactory {
  const UpdateStrategyFactory._();

  static UpdateStrategy forPlatform(
    UpdatePlatform platform, {
    String backendUrl = const String.fromEnvironment('BACKEND_URL'),
    bool releaseMode = kReleaseMode,
  }) => switch (platform) {
    UpdatePlatform.android => PlayUpdateStrategy(),
    UpdatePlatform.windows => WindowsInstallerStrategy(
      backendUrl: backendUrl,
      releaseMode: releaseMode,
    ),
    UpdatePlatform.ios ||
    UpdatePlatform.macos ||
    UpdatePlatform.linux ||
    UpdatePlatform.web => OpenPageStrategy(platform: platform),
  };

  static UpdatePlatform get currentPlatform {
    if (kIsWeb) return UpdatePlatform.web;
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    if (Platform.isIOS) return UpdatePlatform.ios;
    if (Platform.isMacOS) return UpdatePlatform.macos;
    return UpdatePlatform.linux;
  }
}
