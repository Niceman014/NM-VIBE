import 'package:nm_vibe/core/utils/semver.dart';

const pendingUpdateUrl = 'PHASE_4C_DOWNLOAD_URL_PENDING';

class UpdateManifest {
  const UpdateManifest({
    required this.platform,
    required this.channel,
    required this.version,
    required this.minSupportedVersion,
    required this.releaseNotes,
    required this.sha256,
    required this.sizeBytes,
    required this.downloadUrl,
    required this.downloadConfigured,
  });

  final String platform;
  final String channel;
  final String version;
  final String minSupportedVersion;
  final String releaseNotes;
  final String sha256;
  final int sizeBytes;
  final String downloadUrl;
  final bool downloadConfigured;

  factory UpdateManifest.fromJson(Map<String, Object?> json) {
    final version = json['version']?.toString() ?? '';
    final minimum = json['minSupportedVersion']?.toString() ?? '';
    final releaseNotes = json['releaseNotes']?.toString() ?? '';
    final hash = json['sha256']?.toString().toLowerCase() ?? '';
    final size = json['sizeBytes'];
    final url = json['downloadUrl']?.toString() ?? pendingUpdateUrl;
    final platform = json['platform'];
    final channel = json['channel'];
    final parsedVersion = SemVer.tryParse(version);
    final parsedMinimum = SemVer.tryParse(minimum);
    if (parsedVersion == null ||
        parsedMinimum == null ||
        parsedMinimum.compareTo(parsedVersion) > 0 ||
        releaseNotes.length > 5000 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        size is! int ||
        size < 1 ||
        size > 2 * 1024 * 1024 * 1024 ||
        platform != 'windows' ||
        (channel != 'stable' && channel != 'beta')) {
      throw const FormatException('Update information is invalid.');
    }
    final parsedUrl = Uri.tryParse(url);
    final configured =
        url != pendingUpdateUrl &&
        parsedUrl != null &&
        parsedUrl.scheme == 'https' &&
        parsedUrl.host.isNotEmpty &&
        parsedUrl.userInfo.isEmpty;
    if (!configured && url != pendingUpdateUrl) {
      throw const FormatException('Update download configuration is invalid.');
    }
    return UpdateManifest(
      platform: 'windows',
      channel: channel! as String,
      version: version,
      minSupportedVersion: minimum,
      releaseNotes: releaseNotes,
      sha256: hash,
      sizeBytes: size,
      downloadUrl: url,
      downloadConfigured: configured,
    );
  }
}
