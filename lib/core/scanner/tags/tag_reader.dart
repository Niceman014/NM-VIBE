import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

part 'tag_reader_mp3.dart';
part 'tag_reader_id3.dart';
part 'tag_reader_containers.dart';
part 'tag_reader_ogg_wav.dart';
part 'tag_reader_helpers.dart';
part 'tag_reader_binary.dart';

/// Metadata extracted from an audio file by [TagReader].
///
/// Every field is optional: a malformed, truncated or barely tagged file simply
/// yields fewer values. Format-specific containers are parsed first; fallback
/// containers (for example ID3v1 after ID3v2, or a WAV `LIST`/`INFO` chunk
/// after an embedded ID3 tag) only fill gaps via [fillMissingFrom].
class AudioTags {
  AudioTags({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.genre,
    this.year,
    this.trackNumber,
    this.discNumber,
    this.duration,
    this.picture,
    this.pictureMimeType,
  });

  String? title;
  String? artist;
  String? album;
  String? albumArtist;
  String? genre;
  int? year;
  int? trackNumber;
  int? discNumber;
  Duration? duration;

  /// Raw embedded cover image, if any.
  Uint8List? picture;
  String? pictureMimeType;

  /// True when nothing at all (not even a duration) could be parsed.
  bool get isEmpty =>
      title == null &&
      artist == null &&
      album == null &&
      albumArtist == null &&
      genre == null &&
      year == null &&
      trackNumber == null &&
      discNumber == null &&
      duration == null &&
      picture == null;

  bool get hasPicture => picture != null && picture!.isNotEmpty;

  /// Fills every field that is still `null` with the value from [other].
  void fillMissingFrom(AudioTags other) {
    title ??= other.title;
    artist ??= other.artist;
    album ??= other.album;
    albumArtist ??= other.albumArtist;
    genre ??= other.genre;
    year ??= other.year;
    trackNumber ??= other.trackNumber;
    discNumber ??= other.discNumber;
    duration ??= other.duration;
    picture ??= other.picture;
    pictureMimeType ??= other.pictureMimeType;
  }

  @override
  String toString() =>
      'AudioTags(title: $title, artist: $artist, '
      'album: $album, albumArtist: $albumArtist, genre: $genre, year: $year, '
      'track: $trackNumber, disc: $discNumber, duration: $duration, '
      'picture: ${picture?.length ?? 0}B)';
}

/// Reads audio metadata without any platform plugin.
///
/// Supported containers:
/// * MP3 — ID3v2.2/2.3/2.4 plus ID3v1 fallback; duration from a Xing/Info/VBRI
///   header or from the first MPEG frame's bitrate.
/// * FLAC — STREAMINFO duration, VORBIS_COMMENT tags and PICTURE blocks.
/// * MP4/M4A — `moov/mvhd` duration and `ilst` metadata (including `covr`).
/// * OGG/Opus — Vorbis comments and duration from the last page granule.
/// * WAV/RIFF — `fmt ` + `data` duration, `LIST`/`INFO` tags and an embedded
///   `id3 ` chunk delegated to the ID3 parser.
///
/// Reading never throws: whatever could be parsed is returned.
class TagReader {
  const TagReader();

  /// Reads tags from [file]. Never throws.
  AudioTags read(File file) {
    final tags = AudioTags();
    RandomAccessFile? handle;
    try {
      handle = file.openSync();
      final source = _FileByteSource(handle, handle.lengthSync());
      _parseContainer(source, _extensionOf(file.path), tags);
    } catch (_) {
      // Unreadable/vanishing files are normal during a library scan.
    } finally {
      try {
        handle?.closeSync();
      } catch (_) {
        // Ignore close failures.
      }
    }
    return tags;
  }

  /// In-memory variant used by tests and by embedded tag chunks.
  ///
  /// [fileName] only influences the format hint (its extension); the actual
  /// format is detected from the leading bytes first.
  AudioTags readBytes(Uint8List bytes, {String? fileName}) {
    final tags = AudioTags();
    try {
      _parseContainer(
        _MemoryByteSource(bytes),
        fileName == null ? '' : _extensionOf(fileName),
        tags,
      );
    } catch (_) {
      // Defensive: malformed input must never propagate.
    }
    return tags;
  }

  // ---------------------------------------------------------------- dispatch

  void _parseContainer(_ByteSource source, String extension, AudioTags tags) {
    if (source.length <= 0) return;
    final head = source.read(0, 16);

    // ID3v2 may prefix MP3 files and (rarely) FLAC files.
    if (_startsWithAscii(head, 0, 'ID3')) {
      final id3Size = _id3v2SizeFromHeader(head);
      final afterId3 = source.read(id3Size, 8);
      if (_startsWithAscii(afterId3, 0, 'fLaC')) {
        final fallback = AudioTags();
        _parseId3v2(source, 0, fallback);
        _parseFlac(source, tags, startOffset: id3Size);
        tags.fillMissingFrom(fallback);
        return;
      }
      _parseMp3(source, tags);
      return;
    }

    if ((_startsWithAscii(head, 0, 'RIFF') ||
            _startsWithAscii(head, 0, 'RF64')) &&
        _startsWithAscii(head, 8, 'WAVE')) {
      _parseWav(source, tags);
      return;
    }
    if (_startsWithAscii(head, 0, 'fLaC')) {
      _parseFlac(source, tags);
      return;
    }
    if (_startsWithAscii(head, 0, 'OggS')) {
      _parseOgg(source, tags);
      return;
    }
    if (head.length >= 8 && _startsWithAscii(head, 4, 'ftyp')) {
      _parseMp4(source, tags);
      return;
    }

    // Magic was inconclusive — trust the extension as a last resort.
    switch (extension) {
      case '.mp3':
      case '.mp2':
      case '.mp1':
        _parseMp3(source, tags);
      case '.flac':
        _parseFlac(source, tags);
      case '.wav':
      case '.wave':
        _parseWav(source, tags);
      case '.m4a':
      case '.m4b':
      case '.mp4':
      case '.alac':
        _parseMp4(source, tags);
      case '.ogg':
      case '.oga':
      case '.opus':
        _parseOgg(source, tags);
      default:
        // Unknown extension: honour a bare MPEG audio sync word.
        if (head.length >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
          _parseMp3(source, tags);
        }
    }
  }
}
