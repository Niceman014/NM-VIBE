import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.windows) {
    JustAudioMediaKit.ensureInitialized(windows: true, linux: false);
  }
  runApp(const NmVibeApp());
}
