import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:nm_vibe/core/utils/semver.dart';
import '../models/update_manifest.dart';
import 'update_strategy.dart';

typedef InstallerLauncher = Future<void> Function(String installerPath);

class WindowsInstallerStrategy implements UpdateStrategy {
  WindowsInstallerStrategy({
    this.backendUrl = const String.fromEnvironment('BACKEND_URL'),
    this.releaseMode = kReleaseMode,
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
    InstallerLauncher? launchInstaller,
  }) : _client = client ?? http.Client(),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _launchInstaller = launchInstaller ?? _launchExecutable;

  static const int _maxInstallerBytes = 2 * 1024 * 1024 * 1024;
  final String backendUrl;
  final bool releaseMode;
  final http.Client _client;
  final Future<Directory> Function() _directoryProvider;
  final InstallerLauncher _launchInstaller;
  Completer<void>? _abortDownload;

  @override
  Future<UpdateCheckResult> check({required String currentVersion}) async {
    final base = _validatedBackendUri();
    final uri = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}/v1/updates/latest',
      queryParameters: {'platform': 'windows', 'channel': 'stable'},
      fragment: null,
    );
    final request = http.Request('GET', uri)..followRedirects = false;
    try {
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok) {
        throw const UpdateFailure(
          'The update service could not provide update information.',
        );
      }
      final text = await response.stream.bytesToString().timeout(
        const Duration(seconds: 12),
      );
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid update response.');
      }
      final manifest = UpdateManifest.fromJson(decoded);
      final current = SemVer.tryParse(currentVersion);
      final latest = SemVer.tryParse(manifest.version);
      final minimum = SemVer.tryParse(manifest.minSupportedVersion);
      if (current == null || latest == null || minimum == null) {
        throw const FormatException('Invalid version information.');
      }
      if (current.compareTo(latest) >= 0) {
        return const UpdateCheckResult(
          status: UpdateStatus.upToDate,
          manifest: null,
        );
      }
      return UpdateCheckResult(
        status: UpdateStatus.available,
        manifest: manifest,
        requiresUpdate: current.compareTo(minimum) < 0,
      );
    } on UpdateFailure {
      rethrow;
    } on FormatException {
      throw const UpdateFailure(
        'The update service returned invalid information.',
      );
    } on TimeoutException {
      throw const UpdateFailure('The update service timed out.');
    } catch (_) {
      throw const UpdateFailure('Could not check for updates.');
    }
  }

  Uri _validatedBackendUri() {
    final uri = Uri.tryParse(backendUrl.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const UpdateFailure('Online updates are not configured.');
    }
    if (uri.scheme == 'https') return uri;
    if (releaseMode || uri.scheme != 'http' || !_isLocalBackend(uri.host)) {
      throw const UpdateFailure('The update service must use HTTPS.');
    }
    return uri;
  }

  static bool _isLocalBackend(String host) {
    final normalized = host.toLowerCase();
    if (normalized == 'localhost' || normalized == '10.0.2.2') return true;
    final address = InternetAddress.tryParse(normalized);
    if (address == null) return false;
    if (address.isLoopback) return true;
    if (address.type == InternetAddressType.IPv4) {
      final octets = address.rawAddress;
      return octets[0] == 10 ||
          (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31) ||
          (octets[0] == 192 && octets[1] == 168) ||
          (octets[0] == 169 && octets[1] == 254);
    }
    return address.type == InternetAddressType.IPv6 && address.isLinkLocal;
  }

  @override
  Future<void> install(
    UpdateManifest? manifest, {
    required UpdateProgressCallback onProgress,
  }) async {
    if (manifest == null) throw const UpdateFailure('Check for updates first.');
    if (!manifest.downloadConfigured ||
        manifest.downloadUrl == pendingUpdateUrl) {
      throw const UpdateFailure('Installer hosting is not configured yet.');
    }
    if (manifest.sizeBytes < 1 ||
        manifest.sizeBytes > _maxInstallerBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifest.sha256)) {
      throw const UpdateFailure('Installer information is invalid.');
    }
    final uri = Uri.tryParse(manifest.downloadUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const UpdateFailure('Installer downloads must use HTTPS.');
    }

    final abort = Completer<void>();
    _abortDownload = abort;
    File? part;
    RandomAccessFile? output;
    var cancelled = false;
    try {
      final directory = await _directoryProvider();
      final updateDirectory = Directory(p.join(directory.path, 'updates'));
      await updateDirectory.create(recursive: true);
      final safeVersion = manifest.version.replaceAll(
        RegExp(r'[^0-9A-Za-z.+-]'),
        '_',
      );
      part = File(
        p.join(updateDirectory.path, 'nm_vibe_$safeVersion.exe.part'),
      );
      if (await part.exists()) await part.delete();
      output = await part.open(mode: FileMode.write);

      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..followRedirects = false;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        throw const UpdateFailure('The installer download failed.');
      }
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (abort.isCompleted) {
          cancelled = true;
          throw const UpdateCancelled();
        }
        received += chunk.length;
        if (received > manifest.sizeBytes) {
          throw const UpdateFailure(
            'The downloaded installer size did not match.',
          );
        }
        await output.writeFrom(chunk);
        onProgress(UpdateStatus.downloading, received / manifest.sizeBytes);
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != manifest.sizeBytes) {
        throw const UpdateFailure(
          'The downloaded installer size did not match.',
        );
      }

      onProgress(UpdateStatus.verifying, null);
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != manifest.sha256) {
        throw const UpdateFailure(
          'Installer verification failed. The file was removed.',
        );
      }
      final verified = File(
        p.join(updateDirectory.path, 'nm_vibe_$safeVersion.exe'),
      );
      if (await verified.exists()) await verified.delete();
      final installer = await part.rename(verified.path);
      await _launchInstaller(installer.path);
      onProgress(UpdateStatus.launched, 1);
    } on UpdateCancelled {
      cancelled = true;
      rethrow;
    } on UpdateFailure {
      rethrow;
    } on TimeoutException {
      throw const UpdateFailure('The installer download timed out.');
    } catch (_) {
      if (cancelled || abort.isCompleted) throw const UpdateCancelled();
      throw const UpdateFailure(
        'The installer could not be downloaded or started.',
      );
    } finally {
      await output?.close();
      if (part != null && await part.exists()) await part.delete();
      _abortDownload = null;
    }
  }

  @override
  Future<void> cancel() async {
    final abort = _abortDownload;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  void dispose() => _client.close();

  static Future<void> cleanupPartialFiles({
    Future<Directory> Function()? directoryProvider,
  }) async {
    final directory =
        await (directoryProvider ?? getApplicationSupportDirectory)();
    final updates = Directory(p.join(directory.path, 'updates'));
    if (!await updates.exists()) return;
    await for (final entity in updates.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.part')) {
        await entity.delete();
      }
    }
  }

  static Future<void> _launchExecutable(String path) async {
    if (!Platform.isWindows) {
      throw const UpdateFailure('The installer can only run on Windows.');
    }
    await Process.start(path, const [], mode: ProcessStartMode.detached);
  }
}
