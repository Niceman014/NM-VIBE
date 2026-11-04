import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nm_vibe/core/constants/app_constants.dart';
import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/theme/app_theme.dart';
import 'package:nm_vibe/features/updates/views/update_gate.dart';
import 'package:nm_vibe/shared/widgets/app_shell.dart';

class NmVibeApp extends ConsumerWidget {
  const NmVibeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final seed = settings.seedColor;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final useDynamic = settings.useDynamicColor;
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
          themeAnimationDuration:
              WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures
                  .disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 240),
          themeAnimationCurve: Curves.easeInOutCubic,
          theme: AppTheme.light(
            seed,
            dynamicScheme: useDynamic ? lightDynamic : null,
          ),
          darkTheme: AppTheme.dark(
            seed,
            dynamicScheme: useDynamic ? darkDynamic : null,
            pureBlack: settings.usePureBlackTheme,
          ),
          home: const UpdateGate(child: AppShell()),
        );
      },
    );
  }
}
