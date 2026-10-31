import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:nm_vibe/data/models/song_model.dart';
import 'package:nm_vibe/data/sources/music_source.dart';

String? _httpsUrl(Object? value) {
  final text = value?.toString().trim() ?? '';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme == 'https') return uri.toString();
  if (uri.scheme == 'http' &&
      (uri.host == 'creativecommons.org' ||
          uri.host.endsWith('.creativecommons.org'))) {
    return uri.replace(scheme: 'https').toString();
  }
  return null;
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

const String musicApiBaseUrl = String.fromEnvironment(
  'BACKEND_URL',
);

bool _isAllowedBackendUri(Uri uri) {
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  if (!kDebugMode || uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host == '10.0.2.2') return true;
  final address = InternetAddress.tryParse(host);
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

class JamendoTrack implements MusicTrack {
  const JamendoTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.streamUrl,
    this.downloadUrl,
    this.artworkUrl,
    this.licenseUrl,
    this.pageUrl,
  });

  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String album;
  @override
  final Duration duration;
  @override
  final String streamUrl;
  @override
  bool get downloadAllowed => false;
  @override
  final String? downloadUrl;
  @override
  final String? artworkUrl;
  @override
  final String? licenseUrl;
  @override
  final String? pageUrl;
  @override
  String? get codec => 'MP3';
  @override
  int? get bitrateKbps => null;

  @override
  String get sourceId => 'jamendo';

  factory JamendoTrack.fromMap(Map<String, Object?> map) {
    final id = map['id']?.toString().trim() ?? '';
    final streamUrl = _httpsUrl(map['audio']);
    final title = map['name']?.toString().trim() ?? '';
    if (id.isEmpty || title.isEmpty || streamUrl == null) {
      throw const FormatException('Jamendo returned an incomplete track.');
    }
    JamendoService._requireJamendoHost(Uri.parse(streamUrl));

    return JamendoTrack(
      id: id,
      title: title,
      artist: map['artist_name']?.toString().trim() ?? 'Unknown artist',
      album: map['album_name']?.toString().trim() ?? '',
      duration: Duration(seconds: _toInt(map['duration']).clamp(0, 86400)),
      streamUrl: streamUrl,
      downloadUrl: null,
      artworkUrl: _httpsUrl(map['image'] ?? map['album_image']),
      licenseUrl: _httpsUrl(map['license_ccurl']),
      pageUrl: _httpsUrl(map['shareurl']),
    );
  }

  @override
  Song toSong() => Song(
    id: 'jamendo:$id',
    filePath: streamUrl,
    title: title,
    artist: artist,
    album: album,
    albumArtist: artist,
    duration: duration,
    fileSize: 0,
    addedAt: DateTime.now(),
    source: 'jamendo',
    streamUrl: streamUrl,
    downloadUrl: downloadUrl,
    externalPageUrl: pageUrl,
    licenseUrl: licenseUrl,
    remoteArtworkUrl: artworkUrl,
    downloadAllowed: downloadAllowed,
  );
}

/// Search and streaming adapter for Jamendo's licensed catalog.
///
/// The app calls the NM VIBE backend; the Jamendo client ID stays server-side.
/// Offline saving also requires the separate licence gate above, in addition
/// to Jamendo's per-track `audiodownload_allowed` flag.
class JamendoService {
  JamendoService({String? backendBaseUrl, http.Client? client})
    : _backendBaseUrl = (backendBaseUrl ?? musicApiBaseUrl).trim(),
      _client = client ?? http.Client(),
      _ownsClient = client == null;

  final String _backendBaseUrl;
  final http.Client _client;
  final bool _ownsClient;

  bool get isConfigured => _backendUri != null;

  Uri? get _backendUri {
    final uri = Uri.tryParse(_backendBaseUrl);
    if (uri == null || !_isAllowedBackendUri(uri)) {
      return null;
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/$'), ''));
  }

  Future<List<JamendoTrack>> search(
    String query, {
    int limit = 30,
    int page = 1,
  }) async {
    final baseUri = _backendUri;
    if (baseUri == null) {
      throw StateError(
        'Online music is not configured. Set the NM VIBE music API URL.',
      );
    }
    final safeLimit = limit.clamp(1, 50);
    final uri = baseUri.replace(
      path: '${baseUri.path}/v1/music/search',
      queryParameters: <String, String>{
        'q': query.trim(),
        'page': '${page.clamp(1, 1000)}',
        'limit': '$safeLimit',
      },
    );
    final response = await _client
        .get(uri, headers: const <String, String>{'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Jamendo search failed (HTTP ${response.statusCode}).',
        uri: uri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Jamendo returned an invalid response.');
    }
    final results = decoded['results'];
    if (results is! List) {
      throw const FormatException('Jamendo returned no track list.');
    }

    final tracks = <JamendoTrack>[];
    for (final result in results) {
      if (result is! Map) continue;
      try {
        tracks.add(JamendoTrack.fromMap(Map<String, Object?>.from(result)));
      } on FormatException {
        // A malformed catalog row should not hide the other valid results.
      }
    }
    return tracks;
  }

  Future<String?> getStreamUrl(String trackId) async {
    final baseUri = _backendUri;
    if (baseUri == null) {
      throw StateError('Online music is not configured.');
    }
    final uri = baseUri.replace(
      path: '${baseUri.path}/v1/music/stream/${Uri.encodeComponent(trackId)}',
    );
    final response = await _client
        .get(uri, headers: const <String, String>{'Accept': 'application/json'})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Music stream lookup failed (HTTP ${response.statusCode}).',
        uri: uri,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Music backend returned an invalid response.',
      );
    }
    final streamUrl = _httpsUrl(decoded['url']);
    if (streamUrl == null) return null;
    _requireJamendoHost(Uri.parse(streamUrl));
    return streamUrl;
  }

  void close() {
    if (_ownsClient) _client.close();
  }

  static void _requireJamendoHost(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' ||
        !(host == 'jamendo.com' || host.endsWith('.jamendo.com'))) {
      throw const FormatException(
        'Jamendo returned an unexpected download URL.',
      );
    }
  }
}
