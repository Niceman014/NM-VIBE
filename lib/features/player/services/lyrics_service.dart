import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:nm_vibe/data/models/song_model.dart';

/// A single timed lyric line.
class LyricsLine {
  const LyricsLine({required this.time, required this.text});

  final Duration time;
  final String text;

  @override
  String toString() => 'LyricsLine(${time.inMilliseconds}ms, $text)';
}

/// Lyrics for one song, either timestamped ([synced] == true, use [lines]) or
/// plain text ([plainText] != null).
class Lyrics {
  const Lyrics({required this.lines, required this.synced, this.plainText});

  final List<LyricsLine> lines;
  final bool synced;

  /// Full text to display verbatim when [synced] is false; `null` otherwise.
  final String? plainText;

  bool get isEmpty =>
      lines.isEmpty && (plainText == null || plainText!.trim().isEmpty);
}

/// Loads sidecar lyrics for a song: `<name>.lrc` first, then `<name>.txt`.
class LyricsService {
  LyricsService();

  /// Returns `null` when the song has no sidecar lyrics at all.
  Future<Lyrics?> loadFor(Song song) => loadForAudioPath(song.filePath);

  /// File-path variant of [loadFor].
  Future<Lyrics?> loadForAudioPath(String filePath) async {
    final audio = File(filePath);
    final directory = audio.parent;
    final baseName = p.basenameWithoutExtension(audio.path);

    for (final extension in const <String>['.lrc', '.txt']) {
      final file = await _findSidecar(directory, baseName, extension);
      if (file == null) continue;
      final content = await _readText(file);
      if (content == null) continue;
      final lyrics = extension == '.lrc'
          ? parseLrc(content)
          : parsePlain(content);
      if (!lyrics.isEmpty) return lyrics;
    }
    return null;
  }

  /// Parses an LRC document. Timestamps may be repeated on one line; metadata
  /// tags (`[ar:...]`, `[ti:...]`, `[offset:+250]`, ...) are handled, not shown.
  static Lyrics parseLrc(String content) {
    final timed = <LyricsLine>[];
    final untimed = <String>[];
    var offset = Duration.zero;

    for (final rawLine in _splitLines(content)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      // Metadata tags: [ar:Artist], [offset:+500], ... (ignored, except offset)
      for (final match in _metadataPattern.allMatches(line)) {
        final key = match.group(1)!.toLowerCase();
        if (key == 'offset') {
          final value = int.tryParse(match.group(2)!.trim());
          if (value != null) offset = Duration(milliseconds: value);
        }
      }

      final timestampMatches = _timestampPattern.allMatches(line).toList();
      final text = line.replaceAll(_bracketTagPattern, '').trim();
      if (timestampMatches.isEmpty) {
        // Only remember untimed lines when the file has no timestamps at all;
        // mixed LRC files often contain a title/credit line without a time.
        if (text.isNotEmpty && !_metadataPattern.hasMatch(line)) {
          untimed.add(text);
        }
        continue;
      }

      for (final match in timestampMatches) {
        final time = _parseTimestamp(match);
        if (time == null) continue;
        timed.add(LyricsLine(time: time + offset, text: text));
      }
    }

    if (timed.isNotEmpty) {
      timed.sort((a, b) => a.time.compareTo(b.time));
      return Lyrics(lines: timed, synced: true);
    }
    return parsePlain(untimed.join('\n'));
  }

  /// Parses plain (unsynchronised) lyrics.
  static Lyrics parsePlain(String content) {
    final lines = <String>[];
    for (final rawLine in _splitLines(content)) {
      lines.add(rawLine.trimRight());
    }
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) {
      return const Lyrics(lines: <LyricsLine>[], synced: false);
    }
    return Lyrics(
      lines: const <LyricsLine>[],
      synced: false,
      plainText: lines.join('\n'),
    );
  }

  static final RegExp _timestampPattern = RegExp(
    r'\[(?:(\d{1,2}):)?(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
  );
  static final RegExp _metadataPattern = RegExp(
    r'\[([a-zA-Z#][^:\]]*):([^\]]*)\]',
  );
  static final RegExp _bracketTagPattern = RegExp(r'\[[^\]]*\]');

  static Duration? _parseTimestamp(RegExpMatch match) {
    final hours = match.group(1);
    final minutes = match.group(2);
    final seconds = match.group(3);
    final fraction = match.group(4);
    final minuteValue = int.tryParse(minutes ?? '');
    final secondValue = int.tryParse(seconds ?? '');
    if (minuteValue == null || secondValue == null) return null;
    final hourValue = hours == null ? 0 : (int.tryParse(hours) ?? 0);

    var milliseconds = 0;
    if (fraction != null && fraction.isNotEmpty) {
      final value = int.tryParse(fraction) ?? 0;
      switch (fraction.length) {
        case 1:
          milliseconds = value * 100;
        case 2:
          milliseconds = value * 10;
        default:
          milliseconds = value;
      }
    }

    return Duration(
      hours: hourValue,
      minutes: minuteValue,
      seconds: secondValue,
      milliseconds: milliseconds,
    );
  }

  static Iterable<String> _splitLines(String content) {
    return content.split(RegExp(r'\r\n|\r|\n'));
  }

  Future<File?> _findSidecar(
    Directory directory,
    String baseName,
    String extension,
  ) async {
    // Fast path: exact case (most common on all platforms).
    final exact = File(p.join(directory.path, '$baseName$extension'));
    if (await exact.exists()) return exact;

    // Slow path: case-insensitive match on case-sensitive file systems.
    try {
      final lowerBase = baseName.toLowerCase();
      final lowerExtension = extension.toLowerCase();
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (p.extension(name).toLowerCase() != lowerExtension) continue;
        if (p.basenameWithoutExtension(name).toLowerCase() == lowerBase) {
          return entity;
        }
      }
    } catch (_) {
      // Unreadable directory: no lyrics.
    }
    return null;
  }

  Future<String?> _readText(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return _decodeText(bytes);
    } catch (_) {
      return null;
    }
  }

  String? _decodeText(Uint8List bytes) {
    if (bytes.isEmpty) return null;
    // UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(Uint8List.sublistView(bytes, 3), allowMalformed: true);
    }
    // UTF-16 BOM (common for Windows-authored .lrc files)
    if (bytes.length >= 2) {
      if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return _decodeUtf16(
          Uint8List.sublistView(bytes, 2),
          littleEndian: true,
        );
      }
      if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return _decodeUtf16(
          Uint8List.sublistView(bytes, 2),
          littleEndian: false,
        );
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final unit = littleEndian
          ? (bytes[i + 1] << 8) | bytes[i]
          : (bytes[i] << 8) | bytes[i + 1];
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }
}

final lyricsServiceProvider = Provider<LyricsService>((ref) {
  return LyricsService();
});
