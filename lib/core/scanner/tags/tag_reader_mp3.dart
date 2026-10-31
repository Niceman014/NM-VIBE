part of 'tag_reader.dart';

extension _Mp3TagParsing on TagReader {
  // --------------------------------------------------------------------- MP3

  void _parseMp3(_ByteSource source, AudioTags tags) {
    final head = source.read(0, 10);
    var audioStart = 0;
    if (_startsWithAscii(head, 0, 'ID3')) {
      _parseId3v2(source, 0, tags);
      audioStart = _id3v2SizeFromHeader(head);
    }
    _applyMp3Duration(source, audioStart, tags);
    _applyId3v1(source, tags);
  }

  void _applyMp3Duration(_ByteSource source, int audioStart, AudioTags tags) {
    var end = source.length;
    final trailer = source.read(math.max(0, end - 128), 128);
    if (trailer.length == 128 && _startsWithAscii(trailer, 0, 'TAG')) {
      end -= 128;
    }
    if (audioStart < 0 || audioStart >= end) return;

    final windowLength = math.min(end - audioStart, 64 * 1024);
    final window = source.read(audioStart, windowLength);
    if (window.length < 4) return;
    final frame = _findMpegFrame(window);
    if (frame == null) return;

    final frameStart = audioStart + frame.offset;
    final sideInfo = frame.version == 1
        ? (frame.isMono ? 17 : 32)
        : (frame.isMono ? 9 : 17);

    // Xing/Info (CBR/VBR header written by LAME and friends).
    final xing = source.read(frameStart + 4 + sideInfo, 16);
    if (xing.length >= 12 &&
        (_startsWithAscii(xing, 0, 'Xing') ||
            _startsWithAscii(xing, 0, 'Info'))) {
      final flags = _be32(xing, 4);
      if (flags != null && (flags & 0x01) != 0) {
        final frames = _be32(xing, 8);
        final duration = _durationForFrameCount(frame, frames);
        if (duration != null) {
          tags.duration = duration;
          return;
        }
      }
    }

    // VBRI (Fraunhofer encoder).
    final vbri = source.read(frameStart + 4 + 32, 18);
    if (vbri.length >= 18 && _startsWithAscii(vbri, 0, 'VBRI')) {
      final frames = _be32(vbri, 14);
      final duration = _durationForFrameCount(frame, frames);
      if (duration != null) {
        tags.duration = duration;
        return;
      }
    }

    // Last resort: assume the first frame's bitrate for the whole stream.
    final audioBytes = end - frameStart;
    if (audioBytes > 0 && frame.bitrate > 0) {
      tags.duration = Duration(
        microseconds: (audioBytes * 8000000 / frame.bitrate).round(),
      );
    }
  }

  Duration? _durationForFrameCount(_MpegFrameInfo frame, int? frames) {
    if (frames == null || frames <= 0 || frame.sampleRate <= 0) return null;
    final microseconds =
        frames * frame.samplesPerFrame * 1000000 / frame.sampleRate;
    return Duration(microseconds: microseconds.round());
  }

  _MpegFrameInfo? _findMpegFrame(Uint8List data) {
    final limit = math.min(data.length - 4, 65536);
    for (var i = 0; i <= limit; i++) {
      if (data[i] != 0xFF || (data[i + 1] & 0xE0) != 0xE0) continue;
      final frame = _parseMpegHeader(data, i);
      if (frame == null) continue;
      // A real stream has another frame right after this one.
      final next = i + frame.frameLength;
      if (next + 2 <= data.length &&
          !(data[next] == 0xFF && (data[next + 1] & 0xE0) == 0xE0)) {
        continue;
      }
      return frame;
    }
    return null;
  }

  _MpegFrameInfo? _parseMpegHeader(Uint8List data, int offset) {
    if (offset + 4 > data.length) return null;
    final b1 = data[offset + 1];
    final b2 = data[offset + 2];
    final b3 = data[offset + 3];
    final versionBits = (b1 >> 3) & 0x03;
    final layerBits = (b1 >> 1) & 0x03;
    if (versionBits == 1 || layerBits == 0) return null;
    final version = versionBits == 3 ? 1 : (versionBits == 2 ? 2 : 25);
    final layer = layerBits == 3 ? 1 : (layerBits == 2 ? 2 : 3);
    final bitrateIndex = (b2 >> 4) & 0x0F;
    final sampleRateIndex = (b2 >> 2) & 0x03;
    if (bitrateIndex == 0 || bitrateIndex == 15 || sampleRateIndex == 3) {
      return null;
    }
    final padding = (b2 >> 1) & 0x01;
    final isMono = ((b3 >> 6) & 0x03) == 3;
    final bitrate = _mpegBitrate(version, layer, bitrateIndex);
    final sampleRate = _mpegSampleRate(version, sampleRateIndex);
    if (bitrate == null || sampleRate == null || sampleRate <= 0) return null;

    final samplesPerFrame = layer == 1
        ? 384
        : (layer == 2 ? 1152 : (version == 1 ? 1152 : 576));
    final int frameLength;
    if (layer == 1) {
      frameLength = ((12 * bitrate) ~/ sampleRate + padding) * 4;
    } else if (version == 1) {
      frameLength = (144 * bitrate) ~/ sampleRate + padding;
    } else {
      frameLength = (72 * bitrate) ~/ sampleRate + padding;
    }
    if (frameLength < 4) return null;
    return _MpegFrameInfo(
      offset: offset,
      frameLength: frameLength,
      bitrate: bitrate,
      sampleRate: sampleRate,
      samplesPerFrame: samplesPerFrame,
      isMono: isMono,
      version: version,
    );
  }

  int? _mpegBitrate(int version, int layer, int index) {
    const mpeg1Layer1 = <int>[
      0,
      32,
      64,
      96,
      128,
      160,
      192,
      224,
      256,
      288,
      320,
      352,
      384,
      416,
      448,
    ];
    const mpeg1Layer2 = <int>[
      0,
      32,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320,
      384,
    ];
    const mpeg1Layer3 = <int>[
      0,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320,
    ];
    const mpeg2Layer1 = <int>[
      0,
      32,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
      176,
      192,
      224,
      256,
    ];
    const mpeg2Layer23 = <int>[
      0,
      8,
      16,
      24,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
    ];
    if (index < 1 || index > 14) return null;
    final List<int> table;
    if (version == 1) {
      table = layer == 1
          ? mpeg1Layer1
          : (layer == 2 ? mpeg1Layer2 : mpeg1Layer3);
    } else {
      table = layer == 1 ? mpeg2Layer1 : mpeg2Layer23;
    }
    return table[index] * 1000;
  }

  int? _mpegSampleRate(int version, int index) {
    const base = <int>[44100, 48000, 32000];
    if (index < 0 || index > 2) return null;
    if (version == 1) return base[index];
    if (version == 2) return base[index] ~/ 2;
    return base[index] ~/ 4;
  }

  void _applyId3v1(_ByteSource source, AudioTags tags) {
    if (source.length < 128) return;
    final data = source.read(source.length - 128, 128);
    if (data.length < 128 || !_startsWithAscii(data, 0, 'TAG')) return;
    tags.title ??= _id3v1Field(data, 3, 30);
    tags.artist ??= _id3v1Field(data, 33, 30);
    tags.album ??= _id3v1Field(data, 63, 30);
    tags.year ??= _parseYear(_id3v1Field(data, 93, 4));
    // ID3v1.1 stores the track number in the last comment byte.
    if (tags.trackNumber == null && data[125] == 0 && data[126] != 0) {
      tags.trackNumber = data[126];
    }
    if (tags.genre == null) {
      final genreIndex = data[127];
      if (genreIndex != 0xFF && genreIndex < _id3Genres.length) {
        tags.genre = _id3Genres[genreIndex];
      }
    }
  }

  String? _id3v1Field(Uint8List data, int start, int length) {
    final end = math.min(start + length, data.length);
    if (start >= end) return null;
    final slice = Uint8List.sublistView(data, start, end);
    final terminator = slice.indexOf(0);
    final value = latin1.decode(
      terminator < 0 ? slice : slice.sublist(0, terminator),
    );
    return _cleanTagText(value);
  }
}
