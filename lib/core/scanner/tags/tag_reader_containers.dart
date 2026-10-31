part of 'tag_reader.dart';

extension _ContainerTagParsing on TagReader {
  // --------------------------------------------------------------------- FLAC

  void _parseFlac(_ByteSource source, AudioTags tags, {int startOffset = 0}) {
    final marker = source.read(startOffset, 4);
    if (!_startsWithAscii(marker, 0, 'fLaC')) return;
    var pos = startOffset + 4;
    var guard = 0;
    while (pos + 4 <= source.length && guard++ < 1024) {
      final blockHeader = source.read(pos, 4);
      if (blockHeader.length < 4) return;
      final isLast = (blockHeader[0] & 0x80) != 0;
      final type = blockHeader[0] & 0x7F;
      final blockLength = _be24(blockHeader, 1);
      if (blockLength == null || blockLength < 0) return;
      final dataStart = pos + 4;
      if (dataStart + blockLength > source.length) return;
      switch (type) {
        case 0:
          if (blockLength >= 34) {
            _applyFlacStreamInfo(source.read(dataStart, 34), tags);
          }
        case 4:
          if (blockLength <= 16 * 1024 * 1024) {
            _parseVorbisComment(source.read(dataStart, blockLength), tags);
          }
        case 6:
          if (blockLength <= 16 * 1024 * 1024) {
            _parseFlacPicture(source.read(dataStart, blockLength), tags);
          }
        default:
          break;
      }
      pos = dataStart + blockLength;
      if (isLast) break;
    }
  }

  void _applyFlacStreamInfo(Uint8List data, AudioTags tags) {
    if (data.length < 18) return;
    final sampleRate =
        ((data[10] & 0xFF) << 12) |
        ((data[11] & 0xFF) << 4) |
        ((data[12] & 0xF0) >> 4);
    final totalSamples =
        ((data[13] & 0x0F) << 32) |
        ((data[14] & 0xFF) << 24) |
        ((data[15] & 0xFF) << 16) |
        ((data[16] & 0xFF) << 8) |
        (data[17] & 0xFF);
    if (sampleRate <= 0 || totalSamples <= 0) return;
    tags.duration = Duration(
      microseconds: (totalSamples * 1000000 / sampleRate).round(),
    );
  }

  void _parseFlacPicture(Uint8List data, AudioTags tags) {
    var pos = 0;
    final pictureType = _be32(data, pos);
    if (pictureType == null) return;
    pos += 4;
    final mimeLength = _be32(data, pos);
    if (mimeLength == null || mimeLength < 0) return;
    pos += 4;
    if (pos + mimeLength > data.length) return;
    final mime = _latin1(data, pos, mimeLength).trim();
    pos += mimeLength;
    final descriptionLength = _be32(data, pos);
    if (descriptionLength == null || descriptionLength < 0) return;
    pos += 4 + descriptionLength;
    pos += 16; // width + height + colour depth + palette size
    if (pos + 4 > data.length) return;
    final pictureLength = _be32(data, pos);
    if (pictureLength == null || pictureLength <= 0) return;
    pos += 4;
    if (pos + pictureLength > data.length) return;
    final picture = Uint8List.fromList(
      Uint8List.sublistView(data, pos, pos + pictureLength),
    );
    if (picture.isEmpty) return;
    if (tags.picture == null || pictureType == 3) {
      tags.picture = picture;
      tags.pictureMimeType = mime.isEmpty ? _sniffImageMime(picture) : mime;
    }
  }

  // ---------------------------------------------------------------- MP4 / M4A

  void _parseMp4(_ByteSource source, AudioTags tags) {
    final moov = _findTopLevelAtom(source, 'moov');
    if (moov == null) return;
    final length = math.min(moov.dataSize, 64 * 1024 * 1024);
    final data = source.read(moov.dataStart, length);
    if (data.length < 8) return;
    _parseMp4Moov(data, tags);
  }

  void _parseMp4Moov(Uint8List data, AudioTags tags) {
    for (final atom in _childAtoms(data, 0, data.length)) {
      switch (atom.type) {
        case 'mvhd':
          _applyMp4MovieHeader(data, atom, tags);
        case 'udta':
          _parseMp4Udta(data, atom, tags);
        case 'meta':
          _parseMp4Meta(data, atom, tags);
        default:
          break;
      }
    }
  }

  void _parseMp4Udta(Uint8List data, _AtomBounds udta, AudioTags tags) {
    for (final atom in _childAtoms(
      data,
      udta.dataStart,
      udta.dataStart + udta.dataSize,
    )) {
      if (atom.type == 'meta') _parseMp4Meta(data, atom, tags);
    }
  }

  void _parseMp4Meta(Uint8List data, _AtomBounds meta, AudioTags tags) {
    // `meta` is a full box: four bytes of version/flags precede its children.
    final childrenStart = meta.dataStart + 4;
    final childrenEnd = meta.dataStart + meta.dataSize;
    if (childrenStart >= childrenEnd) return;
    for (final atom in _childAtoms(data, childrenStart, childrenEnd)) {
      if (atom.type == 'ilst') _parseMp4Ilst(data, atom, tags);
    }
  }

  void _parseMp4Ilst(Uint8List data, _AtomBounds ilst, AudioTags tags) {
    for (final item in _childAtoms(
      data,
      ilst.dataStart,
      ilst.dataStart + ilst.dataSize,
    )) {
      for (final child in _childAtoms(
        data,
        item.dataStart,
        item.dataStart + item.dataSize,
      )) {
        if (child.type == 'data') {
          _applyMp4Metadata(data, item.type, child, tags);
        }
      }
    }
  }

  void _applyMp4Metadata(
    Uint8List data,
    String itemType,
    _AtomBounds dataAtom,
    AudioTags tags,
  ) {
    final start = dataAtom.dataStart;
    final end = start + dataAtom.dataSize;
    if (end - start < 8) return;
    final typeIndicator = _be32(data, start) ?? 0;
    final valueStart = start + 8;
    final valueEnd = end;
    if (valueStart >= valueEnd) return;
    final text = _mp4Text(data, valueStart, valueEnd, typeIndicator);
    switch (itemType) {
      case '\u00A9nam':
        tags.title = text ?? tags.title;
      case '\u00A9ART':
        tags.artist = text ?? tags.artist;
      case '\u00A9alb':
        tags.album = text ?? tags.album;
      case 'aART':
        tags.albumArtist = text ?? tags.albumArtist;
      case '\u00A9gen':
        tags.genre = _normaliseGenre(text) ?? tags.genre;
      case '\u00A9day':
        tags.year = _parseYear(text) ?? tags.year;
      case 'trkn':
        tags.trackNumber =
            _mp4Counter(data, valueStart, valueEnd) ?? tags.trackNumber;
      case 'disk':
        tags.discNumber =
            _mp4Counter(data, valueStart, valueEnd) ?? tags.discNumber;
      case 'covr':
        if (tags.picture == null) {
          final picture = Uint8List.fromList(
            Uint8List.sublistView(data, valueStart, valueEnd),
          );
          if (picture.isNotEmpty) {
            tags.picture = picture;
            final encoding = typeIndicator & 0xFFFFFF;
            tags.pictureMimeType = encoding == 14
                ? 'image/png'
                : (encoding == 13 ? 'image/jpeg' : _sniffImageMime(picture));
          }
        }
      default:
        break;
    }
  }

  String? _mp4Text(Uint8List data, int start, int end, int typeIndicator) {
    if (end <= start) return null;
    final bytes = Uint8List.sublistView(data, start, end);
    final encoding = typeIndicator & 0xFFFFFF;
    if (encoding == 2) {
      return _cleanTagText(_decodeUtf16(bytes, 0, bigEndian: true));
    }
    return _cleanTagText(utf8.decode(bytes, allowMalformed: true));
  }

  int? _mp4Counter(Uint8List data, int start, int end) {
    if (end - start < 4) return null;
    final value = _be16(data, start + 2);
    if (value == null || value <= 0) return null;
    return value;
  }

  void _applyMp4MovieHeader(Uint8List data, _AtomBounds atom, AudioTags tags) {
    final start = atom.dataStart;
    final end = start + atom.dataSize;
    if (end - start < 20) return;
    final version = data[start];
    int? timescale;
    int? duration;
    if (version == 1) {
      if (end - start < 32) return;
      timescale = _be32(data, start + 20);
      duration = _be64(data, start + 24);
    } else {
      timescale = _be32(data, start + 12);
      duration = _be32(data, start + 16);
      if (duration != null && duration >= 0xFFFFFFFF) return; // unknown
    }
    if (timescale == null || duration == null) return;
    if (timescale <= 0 || duration <= 0) return;
    tags.duration = Duration(
      microseconds: (duration * 1000000 / timescale).round(),
    );
  }

  _AtomBounds? _findTopLevelAtom(_ByteSource source, String type) {
    var pos = 0;
    var guard = 0;
    while (pos + 8 <= source.length && guard++ < 64) {
      final header = source.read(pos, 16);
      if (header.length < 8) return null;
      var size = _be32(header, 0);
      if (size == null) return null;
      final atomType = _latin1(header, 4, 4);
      var headerSize = 8;
      if (size == 1) {
        final large = _be64(header, 8);
        if (large == null) return null;
        size = large;
        headerSize = 16;
      } else if (size == 0) {
        size = source.length - pos;
      }
      if (size < headerSize) return null;
      if (atomType == type) {
        return _AtomBounds(atomType, pos + headerSize, size - headerSize);
      }
      pos += size;
    }
    return null;
  }

  List<_AtomBounds> _childAtoms(Uint8List data, int start, int end) {
    final atoms = <_AtomBounds>[];
    var pos = start;
    while (pos + 8 <= end) {
      var size = _be32(data, pos);
      if (size == null) break;
      final type = _latin1(data, pos + 4, 4);
      var headerSize = 8;
      if (size == 1) {
        final large = _be64(data, pos + 8);
        if (large == null) break;
        size = large;
        headerSize = 16;
      } else if (size == 0) {
        size = end - pos;
      }
      if (size < headerSize) break;
      var atomSize = size;
      if (pos + atomSize > end) atomSize = end - pos; // truncated box
      if (atomSize <= headerSize) break;
      atoms.add(_AtomBounds(type, pos + headerSize, atomSize - headerSize));
      pos += atomSize;
    }
    return atoms;
  }
}
