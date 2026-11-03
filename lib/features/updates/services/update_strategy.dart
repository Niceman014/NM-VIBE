import '../models/update_manifest.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  failed,
  cancelled,
  openedPage,
  launched,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    this.manifest,
    this.requiresUpdate = false,
    this.message,
  });

  final UpdateStatus status;
  final UpdateManifest? manifest;
  final bool requiresUpdate;
  final String? message;
}

typedef UpdateProgressCallback = void Function(
  UpdateStatus status,
  double? progress,
);

abstract interface class UpdateStrategy {
  Future<UpdateCheckResult> check({required String currentVersion});

  Future<void> install(
    UpdateManifest? manifest, {
    required UpdateProgressCallback onProgress,
  });

  Future<void> cancel();

  void dispose();
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}
