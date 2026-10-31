import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:nm_vibe/data/downloads/download_storage.dart';
import 'package:nm_vibe/data/models/song_model.dart';
import 'music_source.dart';

class InternetArchiveTrack implements MusicTrack {
  const InternetArchiveTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.streamUrl,
    required this.downloadUrl,
    required this.licenseStatement,
    required this.codec,
    required this.bitrateKbps,
    this.expectedSizeBytes,
  });

  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  String get album => 'Internet Archive';
  @override
  final Duration duration;
  @override
  final String streamUrl;
  @override
  final String downloadUrl;
  @override
  String? get artworkUrl => null;
  final String licenseStatement;
  @override
  String? get licenseUrl {
    final uri = Uri.tryParse(licenseStatement);
    return uri != null && uri.hasScheme &&
            (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri.replace(scheme: 'https').toString()
        : null;
  }
  @override
  String get pageUrl => 'https://archive.org/details/$id';
  @override
  String get sourceId => 'internet_archive';
  @override
  bool get downloadAllowed => internetArchiveCopyAllowed(licenseStatement);
  @override
  final String codec;
  @override
  final int? bitrateKbps;
  final int? expectedSizeBytes;

  @override
  Song toSong() => Song(
    id: '$sourceId:$id',
    filePath: streamUrl,
    title: title,
    artist: artist,
    album: album,
    albumArtist: artist,
    duration: duration,
    fileSize: 0,
    addedAt: DateTime.now(),
    source: sourceId,
    streamUrl: streamUrl,
    downloadUrl: downloadUrl,
    externalPageUrl: pageUrl,
    licenseUrl: licenseUrl,
    downloadAllowed: downloadAllowed,
  );
}

/// Conservative allow-list: public domain/CC0 and CC BY or BY-SA licenses
/// grant copying with attribution. NC, ND, unknown, and uploader-only rights
/// statements stay stream-only.
bool internetArchiveCopyAllowed(String license) {
  final normalized = license.trim().toLowerCase();
  if (normalized == 'public domain' ||
      normalized == 'public-domain' ||
      normalized == 'cc0' ||
      normalized == 'cc0 1.0' ||
      normalized == 'creative commons zero') {
    return true;
  }
  final uri = Uri.tryParse(license.trim());
  if (uri == null ||
      !{'https', 'http'}.contains(uri.scheme) ||
      uri.host != 'creativecommons.org') {
    return false;
  }
  final path = uri.path.toLowerCase();
  if (path == '/publicdomain/mark/1.0/' ||
      path == '/publicdomain/zero/1.0/' ||
      path == '/publicdomain/zero/1.0') {
    return true;
  }
  return RegExp(
    r'^/licenses/by(-sa)?/(1\.0|2\.0|2\.5|3\.0|4\.0)/?$',
  ).hasMatch(path);
}

class InternetArchiveService {
  InternetArchiveService({
    http.Client? client,
    Connectivity? connectivity,
    bool Function()? wifiOnly,
    this.hasWifi,
    int Function()? storageLimitBytes,
    DownloadStorage? storage,
    http.Client Function()? downloadClientFactory,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _connectivity = connectivity ?? Connectivity(),
       _wifiOnly = wifiOnly ?? (() => false),
       _storageLimitBytes = storageLimitBytes ?? (() => 1024 * 1024 * 1024),
       _storage = storage ?? DownloadStorage(),
       _downloadClientFactory = downloadClientFactory ?? http.Client.new;

  static const _audioExtensions = ['.mp3', '.ogg', '.m4a', '.flac'];
  final http.Client _client;
  final bool _ownsClient;
  final Connectivity _connectivity;
  final bool Function() _wifiOnly;
  final Future<bool> Function()? hasWifi;
  final int Function() _storageLimitBytes;
  final DownloadStorage _storage;
  final http.Client Function() _downloadClientFactory;
  final Map<String, InternetArchiveTrack> _trackCache = {};

  bool get isConfigured => true;

  Future<List<InternetArchiveTrack>> search(String query, {int page = 1}) async {
    final text = query.trim();
    if (text.length > 120 || page < 1 || page > 100) {
      throw ArgumentError('Search text or page is outside the allowed range.');
    }
    final escaped = text.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final searchExpression = text.isEmpty
        ? 'mediatype:audio'
        : 'mediatype:audio AND (title:"$escaped" OR creator:"$escaped")';
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': searchExpression,
      'fl[]': ['identifier', 'title', 'creator', 'licenseurl'],
      'rows': '12',
      'page': '$page',
      'output': 'json',
    });
    final response = await _client
        .get(uri, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw HttpException('Internet Archive search failed (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    Object? docs;
    if (decoded is Map) {
      final responseBody = decoded['response'];
      if (responseBody is Map) docs = responseBody['docs'];
    }
    if (docs is! List) throw const FormatException('Invalid Internet Archive search response.');
    final results = <InternetArchiveTrack>[];
    for (final doc in docs.take(12)) {
      if (doc is! Map) continue;
      final identifier = doc['identifier']?.toString() ?? '';
      if (!RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(identifier)) continue;
      try {
        final track = await _loadTrack(identifier, doc);
        if (track != null) results.add(track);
      } on Object {
        // One unavailable or incomplete archive item must not hide other rows.
      }
    }
    return results;
  }

  Future<InternetArchiveTrack?> _loadTrack(
    String identifier,
    Map doc,
  ) async {
    final cached = _trackCache[identifier];
    if (cached != null) return cached;
    final uri = Uri.https('archive.org', '/metadata/$identifier');
    final response = await _client
        .get(uri, headers: const {'accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['metadata'] is! Map || decoded['files'] is! List) {
      return null;
    }
    final metadata = Map<String, Object?>.from(decoded['metadata'] as Map);
    var license = (metadata['licenseurl'] ?? metadata['rights'])
            ?.toString()
            .trim() ??
        '';
    final licenseUri = Uri.tryParse(license);
    if (licenseUri?.scheme == 'http' &&
        licenseUri?.host == 'creativecommons.org') {
      license = licenseUri!.replace(scheme: 'https').toString();
    }
    final files = (decoded['files'] as List).whereType<Map>().where((file) {
      final name = file['name']?.toString() ?? '';
      final lower = name.toLowerCase();
      return !name.contains('/') &&
          !name.contains('\\') &&
          !name.contains('..') &&
          _audioExtensions.any(lower.endsWith) &&
          file['private']?.toString() != 'true';
    }).toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => _fileRank(a).compareTo(_fileRank(b)));
    final file = files.first;
    final fileName = file['name'].toString();
    final fileUri = Uri.https('archive.org', '/download/$identifier/$fileName');
    final ext = p.extension(fileName).replaceFirst('.', '').toUpperCase();
    final track = InternetArchiveTrack(
      id: identifier,
      title: doc['title']?.toString().trim().isNotEmpty == true
          ? doc['title'].toString().trim()
          : identifier,
      artist: doc['creator']?.toString().trim().isNotEmpty == true
          ? doc['creator'].toString().trim()
          : 'Unknown artist',
      duration: Duration(seconds: _durationSeconds(metadata['runtime'])),
      streamUrl: fileUri.toString(),
      downloadUrl: fileUri.toString(),
      licenseStatement: license.isEmpty ? 'No license declared' : license,
      codec: ext,
      bitrateKbps: int.tryParse(file['bitrate']?.toString() ?? ''),
      expectedSizeBytes: int.tryParse(file['size']?.toString() ?? ''),
    );
    _trackCache[identifier] = track;
    return track;
  }

  int _fileRank(Map file) {
    final name = file['name']?.toString().toLowerCase() ?? '';
    final index = _audioExtensions.indexWhere(name.endsWith);
    final size = int.tryParse(file['size']?.toString() ?? '') ?? 0;
    return index * 1000000 + (size == 0 ? 999999 : size);
  }

  int _durationSeconds(Object? value) {
    final raw = value?.toString() ?? '';
    final number = double.tryParse(raw);
    if (number != null) return number.clamp(0, 86400).round();
    final parts = raw.split(':').map(double.tryParse).toList();
    if (parts.length == 3 && parts.every((item) => item != null)) {
      return (parts[0]! * 3600 + parts[1]! * 60 + parts[2]!).round();
    }
    return 0;
  }

  DownloadTask startDownload(
    InternetArchiveTrack track, {
    required DownloadProgressCallback onProgress,
  }) {
    final completer = Completer<File>();
    final client = _downloadClientFactory();
    var cancelled = false;
    File? temporary;
    Future<void> cancel() async {
      if (cancelled) return;
      cancelled = true;
      client.close();
    }
    unawaited(() async {
      try {
        if (!track.downloadAllowed) {
          throw StateError('This Internet Archive item is stream-only under its recorded license.');
        }
        if (_wifiOnly()) {
          final hasWifiAvailable = hasWifi != null
              ? await hasWifi!()
              : (await _connectivity.checkConnectivity())
                  .contains(ConnectivityResult.wifi);
          if (!hasWifiAvailable) {
            throw StateError('Wi-Fi-only downloads are enabled. Connect to Wi-Fi to continue.');
          }
        }
        if (!InternetArchiveService._isArchiveUrl(track.downloadUrl)) {
          throw const FormatException('Unexpected Internet Archive download URL.');
        }
        final directory = await _storage.sourceDirectory('internet_archive');
        final safeId = track.id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
        final destination = File(p.join(directory.path, '$safeId.${track.codec.toLowerCase()}'));
        if (await destination.exists()) {
          final existingSize = await destination.length();
          await _storage.saveRecord(DownloadRecord(
            id: 'internet_archive:${track.id}',
            source: track.sourceId,
            localPath: destination.path,
            codec: track.codec,
            bitrateKbps: track.bitrateKbps,
            license: track.licenseStatement,
            downloadedAt: await destination.lastModified(),
            sizeBytes: existingSize,
          ));
          if (!completer.isCompleted) completer.complete(destination);
          return;
        }
        final currentBytes = await _storage.sizeBytes();
        if (currentBytes >= _storageLimitBytes()) {
          throw StateError('Download storage limit reached. Delete downloads or raise the limit in Settings.');
        }
        if (track.expectedSizeBytes != null &&
            currentBytes + track.expectedSizeBytes! > _storageLimitBytes()) {
          throw StateError('This download would exceed the configured storage limit.');
        }
        final tempFile = File(p.join(directory.path, '$safeId.part'));
        temporary = tempFile;
        final request = http.Request('GET', Uri.parse(track.downloadUrl));
        final response = await client.send(request).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw HttpException('Internet Archive download failed (${response.statusCode}).');
        }
        final responseUri = response.request?.url;
        if (responseUri != null && !_isArchiveUri(responseUri)) {
          throw const FormatException('Internet Archive redirected to an unexpected host.');
        }
        final total = response.contentLength;
        if (total == null && track.expectedSizeBytes == null) {
          throw StateError('The archive did not provide a verifiable file size.');
        }
        if (total != null && currentBytes + total > _storageLimitBytes()) {
          throw StateError('This download would exceed the configured storage limit.');
        }
        final sink = tempFile.openWrite();
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
            if (cancelled) throw const DownloadCancelled();
            received += chunk.length;
            if (currentBytes + received > _storageLimitBytes()) {
              throw StateError('This download exceeded the configured storage limit.');
            }
            sink.add(chunk);
            onProgress(received, total);
          }
          await sink.flush();
          await sink.close();
        } catch (_) {
          await sink.close();
          rethrow;
        }
        if (cancelled) throw const DownloadCancelled();
        if (received == 0 ||
            (total != null && received != total) ||
            (track.expectedSizeBytes != null &&
                received != track.expectedSizeBytes)) {
          throw const FormatException('Downloaded file size did not match the server response.');
        }
        final file = await tempFile.rename(destination.path);
        final record = DownloadRecord(
          id: 'internet_archive:${track.id}',
          source: track.sourceId,
          localPath: file.path,
          codec: track.codec,
          bitrateKbps: track.bitrateKbps,
          license: track.licenseStatement,
          downloadedAt: DateTime.now().toUtc(),
          sizeBytes: received,
        );
        await _storage.saveRecord(record);
        if (!completer.isCompleted) completer.complete(file);
      } catch (error, stackTrace) {
        final temporaryFile = temporary;
        if (temporaryFile != null && await temporaryFile.exists()) {
          try {
            await temporaryFile.delete();
          } on FileSystemException {
            // Cleanup is retried on the next application startup.
          }
        }
        if (!completer.isCompleted) {
          completer.completeError(cancelled ? const DownloadCancelled() : error, stackTrace);
        }
      } finally {
        client.close();
      }
    }());
    return DownloadTask(completer.future, cancel);
  }

  Future<int> downloadedBytes() => _storage.sizeBytes();
  Future<List<DownloadRecord>> downloadRecords() => _storage.records();
  Future<void> deleteDownloads() => _storage.deleteAll();

  static bool _isArchiveUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && _isArchiveUri(uri);
  }

  static bool _isArchiveUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return uri.scheme == 'https' &&
        (host == 'archive.org' || host.endsWith('.archive.org'));
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

class InternetArchiveMusicSource implements MusicSource {
  const InternetArchiveMusicSource(this.service);

  final InternetArchiveService service;
  @override
  String get id => 'internet_archive';
  @override
  bool get isConfigured => true;
  @override
  bool get canDownload => true;
  @override
  Future<List<MusicTrack>> search(String query, {required int page}) =>
      service.search(query, page: page);
  @override
  Future<String?> getStreamUrl(String trackId) async {
    for (final entry in service._trackCache.values) {
      if (entry.id == trackId) return entry.streamUrl;
    }
    return null;
  }
  @override
  DownloadTask startDownload(
    MusicTrack track, {
    required DownloadProgressCallback onProgress,
  }) {
    if (track is! InternetArchiveTrack) {
      throw ArgumentError.value(track, 'track', 'Expected an Internet Archive track.');
    }
    return service.startDownload(track, onProgress: onProgress);
  }
  @override
  String attributionFor(MusicTrack track) {
    if (track is InternetArchiveTrack) {
      return '${track.title} by ${track.artist} via Internet Archive · ${track.licenseStatement}';
    }
    return '${track.title} by ${track.artist} via Internet Archive';
  }
  @override
  void close() => service.close();
}
