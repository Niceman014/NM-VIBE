part of 'tag_reader.dart';

extension _OggWavTagParsing on TagReader {
  // ------------------------------------------------------------------ OGG/Opus

  void _parseOgg(_ByteSource source, AudioTags tags) {
    final headLength = math.min(source.length, 256 * 1024);
    final head = source.read(0, headLength);
    final packets = <Uint8List>[];
    var builder = BytesBuilder(copy: false);
    var pos = 0;
    while (pos + 27 <= head.length && packets.length < 2) {
      if (!_startsWithAscii(head, pos, 'OggS')) {
        final next = _indexOfAscii(head, 'OggS', pos + 1);
        if (next < 0) break;
        pos = next;
        continue;
      }
      final segmentCount = head[pos + 26];
      final segmentTableStart = pos + 27;
      if (segmentTableStart + segmentCount > head.length) break;
      final lacing = <int>[];
      var bodyLength = 0;
      for (var i = 0; i < segmentCount; i++) {
        final value = head[segmentTableStart + i];
        lacing.add(value);
        bodyLength += value;
      }
      final bodyStart = segmentTableStart + segmentCount;
      if (bodyStart + bodyLength > head.length) break;
      var bodyPos = bodyStart;
      for (final lace in lacing) {
        if (lace > 0) {
          builder.add(Uint8List.sublistView(head, bodyPos, bodyPos + lace));
        }
        bodyPos += lace;
        if (lace < 255) {
          packets.add(builder.takeBytes());
          builder = BytesBuilder(copy: false);
          if (packets.length >= 2) break;
        }
      }
      pos = bodyStart + bodyLength;
    }

    double? sampleRate;
    int? preSkip;
    var isOpus = false;
    if (packets.isNotEmpty) {
      final identification = packets[0];
      if (_asciiEquals(identification, 1, 'vorbis')) {
        final rate = _le32(identification, 12);
        if (rate != null && rate > 0) sampleRate = rate.toDouble();
      } else if (_startsWithAscii(identification, 0, 'OpusHead')) {
        isOpus = true;
        sampleRate = 48000;
        preSkip = _le16(identification, 10);
      }
    }
    if (packets.length > 1) {
      final comment = packets[1];
      if (_asciiEquals(comment, 1, 'vorbis')) {
        _parseVorbisComment(comment, tags, start: 7);
      } else if (_startsWithAscii(comment, 0, 'OpusTags')) {
        _parseVorbisComment(comment, tags, start: 8);
      }
    }

    if (sampleRate != null && sampleRate > 0) {
      final tailLength = math.min(source.length, 128 * 1024);
      final tail = source.read(source.length - tailLength, tailLength);
      final granule = _lastOggGranule(tail);
      if (granule != null && granule > 0) {
        final samples = isOpus ? granule - (preSkip ?? 0) : granule;
        if (samples > 0) {
          tags.duration = Duration(
            microseconds: (samples * 1000000 / sampleRate).round(),
          );
        }
      }
    }
  }

  int? _lastOggGranule(Uint8List tail) {
    var searchEnd = tail.length;
    while (searchEnd > 0) {
      final index = _lastIndexOfAscii(tail, 'OggS', searchEnd);
      if (index < 0) return null;
      if (index + 14 <= tail.length) {
        final granule = _le64Granule(tail, index + 6);
        if (granule != null && granule > 0) return granule;
      }
      searchEnd = index;
    }
    return null;
  }

  int? _le64Granule(Uint8List data, int offset) {
    if (offset < 0 || offset + 8 > data.length) return null;
    if ((data[offset + 7] & 0x80) != 0) return null; // -1 / invalid
    var value = 0;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | (data[offset + i] & 0xFF);
    }
    return value;
  }

  // --------------------------------------------------------------------- WAV

  void _parseWav(_ByteSource source, AudioTags tags) {
    final header = source.read(0, 12);
    if (header.length < 12) return;
    final isRiff =
        _startsWithAscii(header, 0, 'RIFF') ||
        _startsWithAscii(header, 0, 'RF64');
    if (!isRiff || !_startsWithAscii(header, 8, 'WAVE')) return;

    var pos = 12;
    var guard = 0;
    int? byteRate;
    int? sampleRate;
    int? blockAlign;
    int? dataSize;
    int? factSamples;
    final info = <String, String>{};
    Uint8List? id3Chunk;

    while (pos + 8 <= source.length && guard++ < 4096) {
      final chunkHeader = source.read(pos, 8);
      if (chunkHeader.length < 8) break;
      final id = _latin1(chunkHeader, 0, 4);
      final declared = _le32(chunkHeader, 4);
      if (declared == null || declared < 0) break;
      final dataStart = pos + 8;
      final available = source.length - dataStart;
      if (available < 0) break;
      final size = math.min(declared, available);

      switch (id) {
        case 'fmt ':
          final fmt = source.read(dataStart, math.min(size, 40));
          sampleRate = _le32(fmt, 4);
          byteRate = _le32(fmt, 8);
          blockAlign = _le16(fmt, 12);
        case 'data':
          dataSize = declared == 0 ? available : size;
        case 'fact':
          final fact = source.read(dataStart, math.min(size, 4));
          factSamples = _le32(fact, 0);
        case 'LIST':
          info.addAll(
            _parseRiffInfo(source.read(dataStart, math.min(size, 1024 * 1024))),
          );
        case 'id3 ':
        case 'ID3 ':
          id3Chunk = source.read(dataStart, math.min(size, 32 * 1024 * 1024));
        default:
          break;
      }

      final advance = declared + (declared.isOdd ? 1 : 0);
      if (advance <= 0) break;
      pos = dataStart + advance;
    }

    if (byteRate == null &&
        sampleRate != null &&
        blockAlign != null &&
        sampleRate > 0) {
      byteRate = sampleRate * blockAlign;
    }
    if (dataSize != null && byteRate != null && byteRate > 0 && dataSize > 0) {
      tags.duration = Duration(
        microseconds: (dataSize * 1000000 / byteRate).round(),
      );
    } else if (factSamples != null &&
        sampleRate != null &&
        sampleRate > 0 &&
        factSamples > 0) {
      tags.duration = Duration(
        microseconds: (factSamples * 1000000 / sampleRate).round(),
      );
    }

    // ID3 tags embedded in a WAV chunk win over plain LIST/INFO fields.
    if (id3Chunk != null && id3Chunk.isNotEmpty) {
      final fallback = AudioTags();
      _parseId3v2Data(id3Chunk, fallback);
      tags.fillMissingFrom(fallback);
    }
    tags.title ??= _cleanTagText(info['INAM']);
    tags.artist ??= _cleanTagText(info['IART']);
    tags.album ??= _cleanTagText(info['IPRD']);
    tags.genre ??= _cleanTagText(info['IGNR']);
    tags.year ??= _parseYear(_cleanTagText(info['ICRD']));
  }

  Map<String, String> _parseRiffInfo(Uint8List data) {
    final result = <String, String>{};
    var pos = 0;
    // A LIST chunk of type INFO starts with the literal "INFO".
    if (_startsWithAscii(data, 0, 'INFO')) pos = 4;
    var guard = 0;
    while (pos + 8 <= data.length && guard++ < 512) {
      final id = _latin1(data, pos, 4);
      final size = _le32(data, pos + 4);
      if (size == null || size < 0) break;
      final start = pos + 8;
      if (start + size > data.length) break;
      final value = _cleanTagText(
        latin1.decode(Uint8List.sublistView(data, start, start + size)),
      );
      if (value != null && value.isNotEmpty) result[id] = value;
      pos = start + size + (size.isOdd ? 1 : 0);
    }
    return result;
  }

  // ------------------------------------------------------------- Vorbis comments

  void _parseVorbisComment(Uint8List data, AudioTags tags, {int start = 0}) {
    var pos = start;
    final vendorLength = _le32(data, pos);
    if (vendorLength == null || vendorLength < 0) return;
    pos += 4 + vendorLength;
    final count = _le32(data, pos);
    if (count == null) return;
    pos += 4;
    final limit = math.min(count, 4096);
    for (var i = 0; i < limit; i++) {
      final length = _le32(data, pos);
      if (length == null || length < 0) return;
      final valueStart = pos + 4;
      final valueEnd = valueStart + length;
      if (valueStart >= data.length) return;
      final safeEnd = math.min(valueEnd, data.length);
      _applyVorbisField(
        utf8.decode(
          Uint8List.sublistView(data, valueStart, safeEnd),
          allowMalformed: true,
        ),
        tags,
      );
      if (valueEnd > data.length) return;
      pos = valueEnd;
    }
  }

  void _applyVorbisField(String field, AudioTags tags) {
    final separator = field.indexOf('=');
    if (separator <= 0) return;
    final key = field.substring(0, separator).trim().toUpperCase();
    final value = _cleanTagText(field.substring(separator + 1));
    if (value == null) return;
    switch (key) {
      case 'TITLE':
        tags.title = value;
      case 'ARTIST':
        tags.artist = value;
      case 'ALBUM':
        tags.album = value;
      case 'ALBUMARTIST':
      case 'ALBUM ARTIST':
      case 'ALBUM_ARTIST':
        tags.albumArtist = value;
      case 'GENRE':
        tags.genre = value;
      case 'DATE':
      case 'YEAR':
        tags.year = _parseYear(value) ?? tags.year;
      case 'TRACKNUMBER':
      case 'TRACK':
        tags.trackNumber = _parseLeadingNumber(value) ?? tags.trackNumber;
      case 'DISCNUMBER':
      case 'DISC':
        tags.discNumber = _parseLeadingNumber(value) ?? tags.discNumber;
      default:
        break;
    }
  }
}
