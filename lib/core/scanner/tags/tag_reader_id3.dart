part of 'tag_reader.dart';

extension _Id3TagParsing on TagReader {
  // -------------------------------------------------------------------- ID3v2

  int _id3v2SizeFromHeader(Uint8List header) {
    if (header.length < 10 || !_startsWithAscii(header, 0, 'ID3')) return 0;
    final major = header[3];
    final flags = header[5];
    final size = _syncSafeFrom(header, 6);
    if (size == null || size <= 0) return 0;
    var total = 10 + size;
    if (major >= 4 && (flags & 0x10) != 0) total += 10;
    return total;
  }

  void _parseId3v2(_ByteSource source, int offset, AudioTags tags) {
    final header = source.read(offset, 10);
    if (header.length < 10 || !_startsWithAscii(header, 0, 'ID3')) return;
    final major = header[3];
    if (major < 2) return;
    final flags = header[5];
    final declared = _syncSafeFrom(header, 6);
    if (declared == null || declared <= 0) return;
    final available = source.length - offset - 10;
    if (available <= 0) return;
    final length = math.min(declared, available);
    var body = source.read(offset + 10, length);
    if (body.isEmpty) return;
    var unsynchronised = false;
    if ((flags & 0x80) != 0) {
      body = _removeUnsynchronisation(body);
      unsynchronised = true;
    }
    _parseId3v2Frames(
      body,
      major,
      flags,
      tags,
      alreadyUnsynced: unsynchronised,
    );
  }

  /// Parses a complete ID3v2 tag from memory (used for WAV `id3 ` chunks).
  void _parseId3v2Data(Uint8List tagBytes, AudioTags tags) {
    if (tagBytes.length < 10 || !_startsWithAscii(tagBytes, 0, 'ID3')) return;
    final major = tagBytes[3];
    if (major < 2) return;
    final flags = tagBytes[5];
    final declared = _syncSafeFrom(tagBytes, 6);
    if (declared == null || declared <= 0) return;
    final end = math.min(tagBytes.length, 10 + declared);
    if (end <= 10) return;
    var body = Uint8List.sublistView(tagBytes, 10, end);
    var unsynchronised = false;
    if ((flags & 0x80) != 0) {
      body = _removeUnsynchronisation(body);
      unsynchronised = true;
    }
    _parseId3v2Frames(
      body,
      major,
      flags,
      tags,
      alreadyUnsynced: unsynchronised,
    );
  }

  void _parseId3v2Frames(
    Uint8List body,
    int major,
    int tagFlags,
    AudioTags tags, {
    bool alreadyUnsynced = false,
  }) {
    var pos = 0;
    // Extended header is not needed, but must be skipped.
    if ((tagFlags & 0x40) != 0) {
      if (major == 4) {
        final extendedSize = _syncSafeFrom(body, 0);
        if (extendedSize != null && extendedSize > 0) {
          pos = math.min(extendedSize, body.length);
        }
      } else {
        final extendedSize = _be32(body, 0);
        if (extendedSize != null && extendedSize > 0) {
          pos = math.min(extendedSize + 4, body.length);
        }
      }
    }

    final headerSize = major == 2 ? 6 : 10;
    final idLength = major == 2 ? 3 : 4;
    while (pos + headerSize <= body.length) {
      final id = _latin1(body, pos, idLength);
      if (id.isEmpty || id.codeUnitAt(0) == 0) break; // padding
      if (!_isValidFrameId(id)) break;

      final size = major == 2
          ? _be24(body, pos + 3)
          : (major == 4 ? _syncSafeFrom(body, pos + 4) : _be32(body, pos + 4));
      if (size == null || size <= 0) break;
      final frameFlags = major == 2 ? 0 : (_be16(body, pos + 8) ?? 0);
      final dataStart = pos + headerSize;
      final available = body.length - dataStart;
      if (available <= 0) break;
      final frameLength = math.min(size, available);
      var payload = Uint8List.sublistView(
        body,
        dataStart,
        dataStart + frameLength,
      );
      if (major >= 4 && !alreadyUnsynced && (frameFlags & 0x0002) != 0) {
        payload = _removeUnsynchronisation(payload);
      }
      _handleId3Frame(id, payload, major, tags);

      if (size > available) break; // truncated final frame
      pos = dataStart + size;
    }
  }

  bool _isValidFrameId(String id) {
    for (var i = 0; i < id.length; i++) {
      final code = id.codeUnitAt(i);
      final valid =
          (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A);
      if (!valid) return false;
    }
    return id.isNotEmpty;
  }

  void _handleId3Frame(
    String id,
    Uint8List payload,
    int major,
    AudioTags tags,
  ) {
    if (payload.isEmpty) return;
    switch (id) {
      case 'TIT2':
      case 'TT2':
        tags.title = _decodeId3Text(payload) ?? tags.title;
      case 'TPE1':
      case 'TP1':
        tags.artist = _decodeId3Text(payload) ?? tags.artist;
      case 'TALB':
      case 'TAL':
        tags.album = _decodeId3Text(payload) ?? tags.album;
      case 'TPE2':
      case 'TP2':
        tags.albumArtist = _decodeId3Text(payload) ?? tags.albumArtist;
      case 'TCON':
      case 'TCO':
        tags.genre = _normaliseGenre(_decodeId3Text(payload)) ?? tags.genre;
      case 'TYER':
      case 'TYE':
      case 'TDRC':
        tags.year = _parseYear(_decodeId3Text(payload)) ?? tags.year;
      case 'TRCK':
      case 'TRK':
        tags.trackNumber =
            _parseLeadingNumber(_decodeId3Text(payload)) ?? tags.trackNumber;
      case 'TPOS':
      case 'TPA':
        tags.discNumber =
            _parseLeadingNumber(_decodeId3Text(payload)) ?? tags.discNumber;
      case 'APIC':
      case 'PIC':
        _parseId3Picture(payload, tags, version22: id == 'PIC');
      default:
        break;
    }
  }

  void _parseId3Picture(
    Uint8List payload,
    AudioTags tags, {
    required bool version22,
  }) {
    if (payload.length < 5) return;
    final encoding = payload[0];
    var pos = 1;
    String mime;
    if (version22) {
      if (pos + 3 > payload.length) return;
      final format = _latin1(payload, pos, 3).toUpperCase();
      pos += 3;
      mime = format == 'PNG' ? 'image/png' : 'image/jpeg';
    } else {
      final mimeEnd = payload.indexOf(0, pos);
      if (mimeEnd < 0 || mimeEnd >= payload.length) return;
      mime = latin1.decode(Uint8List.sublistView(payload, pos, mimeEnd)).trim();
      pos = mimeEnd + 1;
    }
    if (pos >= payload.length) return;
    final pictureType = payload[pos];
    pos++;
    pos = _skipEncodedText(payload, pos, encoding);
    if (pos < 0 || pos >= payload.length) return;
    final picture = Uint8List.fromList(
      Uint8List.sublistView(payload, pos, payload.length),
    );
    if (picture.isEmpty) return;
    // Prefer the front cover over any other embedded image.
    if (tags.picture == null || pictureType == 3) {
      tags.picture = picture;
      tags.pictureMimeType = mime.isEmpty ? _sniffImageMime(picture) : mime;
    }
  }

  /// Skips a null-terminated ID3 string, returning the index after it.
  int _skipEncodedText(Uint8List data, int start, int encoding) {
    if (start >= data.length) return -1;
    if (encoding == 0 || encoding == 3) {
      final terminator = data.indexOf(0, start);
      return terminator < 0 ? data.length : terminator + 1;
    }
    for (var i = start; i + 1 < data.length; i += 2) {
      final unit = encoding == 1
          ? (data[i] << 8) | data[i + 1]
          : (data[i] << 8) | data[i + 1];
      if (unit == 0) return i + 2;
    }
    return data.length;
  }

  String? _decodeId3Text(Uint8List payload) {
    if (payload.isEmpty) return null;
    final encoding = payload[0];
    const start = 1;
    if (start >= payload.length) return null;
    switch (encoding) {
      case 0:
        return _nullTerminatedText(payload, start, latin1.decode);
      case 1:
      case 2:
        return _cleanTagText(
          _decodeUtf16(payload, start, bigEndian: encoding == 2),
        );
      case 3:
        return _nullTerminatedText(
          payload,
          start,
          (bytes) => utf8.decode(bytes, allowMalformed: true),
        );
      default:
        return _nullTerminatedText(payload, start, latin1.decode);
    }
  }

  String? _nullTerminatedText(
    Uint8List data,
    int start,
    String Function(Uint8List bytes) decode,
  ) {
    if (start >= data.length) return null;
    final terminator = data.indexOf(0, start);
    final end = terminator < 0 ? data.length : terminator;
    if (end <= start) return null;
    return _cleanTagText(decode(Uint8List.sublistView(data, start, end)));
  }

  String _decodeUtf16(Uint8List data, int start, {required bool bigEndian}) {
    var offset = start;
    var big = bigEndian;
    if (offset + 1 < data.length) {
      if (data[offset] == 0xFF && data[offset + 1] == 0xFE) {
        big = false;
        offset += 2;
      } else if (data[offset] == 0xFE && data[offset + 1] == 0xFF) {
        big = true;
        offset += 2;
      }
    }
    final units = <int>[];
    for (var i = offset; i + 1 < data.length; i += 2) {
      final unit = big
          ? (data[i] << 8) | data[i + 1]
          : (data[i + 1] << 8) | data[i];
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }
}
