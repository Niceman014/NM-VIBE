import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:nm_vibe/shared/providers/app_providers.dart';
import 'package:nm_vibe/core/storage/settings_service.dart';
import 'package:nm_vibe/data/models/song_model.dart';

void main() {
  group('sortSongs', () {
    final songs = [
      Song(
        id: 'b',
        filePath: r'C:\music\b.mp3',
        title: 'Beta',
        artist: 'Zulu',
        album: 'Second',
        albumArtist: 'Zulu',
        duration: const Duration(minutes: 3),
        fileSize: 3,
        addedAt: DateTime(2024, 1, 2),
        trackNumber: 2,
      ),
      Song(
        id: 'a',
        filePath: r'C:\music\a.mp3',
        title: 'Alpha',
        artist: 'Alpha',
        album: 'First',
        albumArtist: 'Alpha',
        duration: const Duration(minutes: 4),
        fileSize: 4,
        addedAt: DateTime(2024, 1, 1),
        trackNumber: 1,
      ),
    ];

    test('sorts by title ascending', () {
      final sorted = sortSongs(songs, SongsSortMode.title);
      expect(sorted.map((song) => song.title), ['Alpha', 'Beta']);
    });

    test('sorts by title descending', () {
      final sorted = sortSongs(songs, SongsSortMode.title, ascending: false);
      expect(sorted.map((song) => song.title), ['Beta', 'Alpha']);
    });

    test('sorts by duration', () {
      final sorted = sortSongs(songs, SongsSortMode.duration);
      expect(sorted.first.title, 'Beta');
    });

    test('sorts by date added', () {
      final sorted = sortSongs(songs, SongsSortMode.dateAdded);
      expect(sorted.first.title, 'Alpha');
    });
  });

  group('AppSettings defaults', () {
    test('has a seed colour and system theme', () {
      const settings = AppSettings();
      expect(settings.themeMode, ThemeMode.system);
      expect(settings.seedColorValue, isNot(0));
      expect(settings.libraryFolders, isEmpty);
    });
  });
}
