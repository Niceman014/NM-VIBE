import 'dart:io';

import 'package:flutter/foundation.dart';

/// Platform capability probes used to branch behaviour without scattering
/// `Platform.isX` checks through the UI.
class PlatformInfo {
  PlatformInfo._();

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  static bool get isMobile => isAndroid || isIOS;
  static bool get isDesktop => isWindows || isLinux || isMacOS;

  /// audio_service can provide a media notification / lock-screen controls.
  static bool get supportsBackgroundAudio => isAndroid || isIOS;

  /// just_audio exposes AndroidEqualizer only on Android.
  static bool get supportsEqualizer => isAndroid;

  /// Android reads the library through MediaStore instead of walking folders.
  static bool get usesMediaStoreScanner => isAndroid;

  static String get platformName {
    if (isAndroid) return 'Android';
    if (isIOS) return 'iOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    if (isMacOS) return 'macOS';
    return 'Unknown';
  }
}
