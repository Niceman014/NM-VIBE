import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/features/updates/controllers/update_controller.dart';
import 'package:nm_vibe/features/updates/models/update_manifest.dart';
import 'package:nm_vibe/features/updates/services/update_strategy.dart';
import 'package:nm_vibe/features/updates/views/update_gate.dart';

void main() {
  testWidgets(
    'mandatory update blocks normal navigation but offers offline music',
    (tester) async {
      final controller = _RequiredUpdateController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(home: UpdateGate(child: Text('Normal app'))),
        ),
      );
      await tester.pump();

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Normal app'), findsNothing);
      expect(find.text('Play offline music'), findsOneWidget);
      expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
    },
  );
}

class _RequiredUpdateController extends UpdateController {
  _RequiredUpdateController() : super(_UnusedStrategy()) {
    state = UpdateUiState(
      status: UpdateStatus.available,
      currentVersion: '1.0.0',
      manifest: const UpdateManifest(
        platform: 'windows',
        channel: 'stable',
        version: '2.0.0',
        minSupportedVersion: '1.5.0',
        releaseNotes: 'Security updates.',
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
        sizeBytes: 10,
        downloadUrl: pendingUpdateUrl,
        downloadConfigured: false,
      ),
      requiresUpdate: true,
    );
  }

  @override
  Future<void> checkForUpdates({bool automatic = false}) async {}
}

class _UnusedStrategy implements UpdateStrategy {
  @override
  Future<UpdateCheckResult> check({required String currentVersion}) async =>
      const UpdateCheckResult(status: UpdateStatus.upToDate);

  @override
  Future<void> install(
    UpdateManifest? manifest, {
    required UpdateProgressCallback onProgress,
  }) async {}

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}
}
