import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nm_vibe/data/sources/jamendo_service.dart';
import 'package:nm_vibe/data/models/song_model.dart';

void main() {
  test('rejects non-local HTTP backend URLs in debug builds', () {
    final service = JamendoService(backendBaseUrl: 'http://music.example.com');
    expect(service.isConfigured, isFalse);
    service.close();
  });

  test('allows local HTTP in debug and HTTPS in all build modes', () {
    final local = JamendoService(backendBaseUrl: 'http://10.0.2.2:8080');
    final secure = JamendoService(backendBaseUrl: 'https://music.example.com');
    expect(local.isConfigured, isTrue);
    expect(secure.isConfigured, isTrue);
    local.close();
    secure.close();
  });

  test('missing BACKEND_URL disables Jamendo without throwing during setup', () async {
    final service = JamendoService(backendBaseUrl: '');
    expect(service.isConfigured, isFalse);
    await expectLater(service.search('ambient'), throwsStateError);
    service.close();
  });

  group('JamendoTrack', () {
    test('maps a licensed stream and per-track download permission', () {
      final track = JamendoTrack.fromMap(<String, Object?>{
        'id': '12345',
        'name': 'Afterglow',
        'artist_name': 'Nova Kane',
        'album_name': 'First Light',
        'duration': '185',
        'audio': 'https://prod-1.storage.jamendo.com/?trackid=12345',
        'audiodownload':
            'https://prod-1.storage.jamendo.com/download/track/12345/mp32/',
        'audiodownload_allowed': true,
        'license_ccurl': 'http://creativecommons.org/licenses/by/4.0/',
        'image': 'https://usercontent.jamendo.com/cover.jpg',
        'shareurl': 'https://www.jamendo.com/track/12345',
      });

      final song = track.toSong();
      expect(song.id, 'jamendo:12345');
      expect(song.isOnlineTrack, isTrue);
      expect(song.streamUrl, track.streamUrl);
      expect(song.downloadAllowed, isFalse);
      expect(song.licenseUrl, 'https://creativecommons.org/licenses/by/4.0/');
      expect(song.remoteArtworkUrl, track.artworkUrl);
      final restored = Song.fromMap(song.toMap());
      expect(restored.streamUrl, song.streamUrl);
      expect(restored.downloadAllowed, isFalse);
      expect(restored.isDownloaded, isFalse);
    });

    test('rejects insecure or non-Jamendo audio URLs', () {
      expect(
        () => JamendoTrack.fromMap(<String, Object?>{
          'id': '1',
          'name': 'Track',
          'audio': 'https://example.com/audio.mp3',
        }),
        throwsFormatException,
      );
      expect(
        () => JamendoTrack.fromMap(<String, Object?>{
          'id': '1',
          'name': 'Track',
          'audio': 'http://prod-1.storage.jamendo.com/audio.mp3',
        }),
        throwsFormatException,
      );
    });
  });

  test('search goes through the backend and parses catalog rows', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'music.example.com');
      expect(request.url.path, '/v1/music/search');
      expect(request.url.queryParameters['q'], 'ambient piano');
      expect(request.url.queryParameters['page'], '1');
      return http.Response(
        jsonEncode(<String, Object?>{
          'results': <Object?>[
            <String, Object?>{
              'id': 7,
              'name': 'Quiet Morning',
              'artist_name': 'Mira',
              'duration': 180,
              'audio': 'https://prod-1.storage.jamendo.com/?trackid=7',
              'audiodownload_allowed': false,
            },
          ],
        }),
        200,
      );
    });
    final service = JamendoService(
      backendBaseUrl: 'https://music.example.com',
      client: client,
    );
    addTearDown(service.close);

    final tracks = await service.search('ambient piano');
    expect(tracks, hasLength(1));
    expect(tracks.single.id, '7');
    expect(tracks.single.downloadAllowed, isFalse);
  });

  test('Jamendo track download data is ignored and remains stream-only', () {
    final track = JamendoTrack.fromMap(<String, Object?>{
      'id': '12345',
      'name': 'Afterglow',
      'audio': 'https://prod-1.storage.jamendo.com/?trackid=12345',
      'audiodownload': 'https://prod-1.storage.jamendo.com/download/12345.mp3',
      'audiodownload_allowed': true,
    });
    expect(track.downloadAllowed, isFalse);
    expect(track.downloadUrl, isNull);
  });
}
