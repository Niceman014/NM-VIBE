part of 'tag_reader.dart';

/// Small constants shared by all ID3 genre mappings (ID3v1 standard list).
const List<String> _id3Genres = <String>[
  'Blues',
  'Classic Rock',
  'Country',
  'Dance',
  'Disco',
  'Funk',
  'Grunge',
  'Hip-Hop',
  'Jazz',
  'Metal',
  'New Age',
  'Oldies',
  'Other',
  'Pop',
  'R&B',
  'Rap',
  'Reggae',
  'Rock',
  'Techno',
  'Industrial',
  'Alternative',
  'Ska',
  'Death Metal',
  'Pranks',
  'Soundtrack',
  'Euro-Techno',
  'Ambient',
  'Trip-Hop',
  'Vocal',
  'Jazz+Funk',
  'Fusion',
  'Trance',
  'Classical',
  'Instrumental',
  'Acid',
  'House',
  'Game',
  'Sound Clip',
  'Gospel',
  'Noise',
  'Alternative Rock',
  'Bass',
  'Soul',
  'Punk',
  'Space',
  'Meditative',
  'Instrumental Pop',
  'Instrumental Rock',
  'Ethnic',
  'Gothic',
  'Darkwave',
  'Techno-Industrial',
  'Electronic',
  'Pop-Folk',
  'Eurodance',
  'Dream',
  'Southern Rock',
  'Comedy',
  'Cult',
  'Gangsta Rap',
  'Top 40',
  'Christian Rap',
  'Pop/Funk',
  'Jungle',
  'Native American',
  'Cabaret',
  'New Wave',
  'Psychedelic',
  'Rave',
  'Show Tunes',
  'Trailer',
  'Lo-Fi',
  'Tribal',
  'Acid Punk',
  'Acid Jazz',
  'Polka',
  'Retro',
  'Musical',
  'Rock & Roll',
  'Hard Rock',
];

bool _startsWithAscii(Uint8List data, int offset, String value) {
  if (offset < 0 || offset + value.length > data.length) return false;
  for (var i = 0; i < value.length; i++) {
    if (data[offset + i] != value.codeUnitAt(i)) return false;
  }
  return true;
}

bool _asciiEquals(Uint8List data, int offset, String value) =>
    _startsWithAscii(data, offset, value);

String _latin1(Uint8List data, int offset, int length) {
  if (offset < 0 || offset >= data.length) return '';
  final end = math.min(offset + length, data.length);
  return latin1.decode(Uint8List.sublistView(data, offset, end));
}

int? _syncSafeFrom(Uint8List data, int offset) {
  if (offset < 0 || offset + 4 > data.length) return null;
  return ((data[offset] & 0x7F) << 21) |
      ((data[offset + 1] & 0x7F) << 14) |
      ((data[offset + 2] & 0x7F) << 7) |
      (data[offset + 3] & 0x7F);
}

int? _be16(Uint8List data, int offset) {
  if (offset < 0 || offset + 2 > data.length) return null;
  return (data[offset] << 8) | data[offset + 1];
}

int? _be24(Uint8List data, int offset) {
  if (offset < 0 || offset + 3 > data.length) return null;
  return (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
}

int? _be32(Uint8List data, int offset) {
  if (offset < 0 || offset + 4 > data.length) return null;
  return (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
}

int? _be64(Uint8List data, int offset) {
  if (offset < 0 || offset + 8 > data.length) return null;
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | data[offset + i];
  }
  return value;
}

int? _le16(Uint8List data, int offset) {
  if (offset < 0 || offset + 2 > data.length) return null;
  return data[offset] | (data[offset + 1] << 8);
}

int? _le32(Uint8List data, int offset) {
  if (offset < 0 || offset + 4 > data.length) return null;
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

int _indexOfAscii(Uint8List data, String value, int start) {
  if (start < 0) start = 0;
  final last = data.length - value.length;
  for (var i = start; i <= last; i++) {
    if (_startsWithAscii(data, i, value)) return i;
  }
  return -1;
}

int _lastIndexOfAscii(Uint8List data, String value, int end) {
  final last = math.min(end, data.length) - value.length;
  for (var i = last; i >= 0; i--) {
    if (_startsWithAscii(data, i, value)) return i;
  }
  return -1;
}

/// Abstract random-access byte source: files stream lazily, tests use memory.
abstract class _ByteSource {
  int get length;
  Uint8List read(int offset, int count);
}

class _MemoryByteSource implements _ByteSource {
  _MemoryByteSource(this._bytes);

  final Uint8List _bytes;

  @override
  int get length => _bytes.length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count <= 0 || offset >= _bytes.length) {
      return Uint8List(0);
    }
    final end = math.min(offset + count, _bytes.length);
    return Uint8List.sublistView(_bytes, offset, end);
  }
}

class _FileByteSource implements _ByteSource {
  _FileByteSource(this._file, this.length);

  final RandomAccessFile _file;

  @override
  final int length;

  @override
  Uint8List read(int offset, int count) {
    if (offset < 0 || count <= 0 || offset >= length) return Uint8List(0);
    final safeCount = math.min(count, length - offset);
    try {
      _file.setPositionSync(offset);
      return _file.readSync(safeCount);
    } catch (_) {
      return Uint8List(0);
    }
  }
}

class _AtomBounds {
  const _AtomBounds(this.type, this.dataStart, this.dataSize);

  final String type;
  final int dataStart;
  final int dataSize;
}

class _MpegFrameInfo {
  const _MpegFrameInfo({
    required this.offset,
    required this.frameLength,
    required this.bitrate,
    required this.sampleRate,
    required this.samplesPerFrame,
    required this.isMono,
    required this.version,
  });

  final int offset;
  final int frameLength;
  final int bitrate;
  final int sampleRate;
  final int samplesPerFrame;
  final bool isMono;
  final int version;
}
