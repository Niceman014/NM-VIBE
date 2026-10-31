part of 'tag_reader.dart';

extension _TagReaderHelpers on TagReader {
  // ------------------------------------------------------------------ helpers

  String _extensionOf(String path) {
    final base = p.basename(path);
    final dot = base.lastIndexOf('.');
    if (dot <= 0 || dot == base.length - 1) return '';
    return base.substring(dot).toLowerCase();
  }

  Uint8List _removeUnsynchronisation(Uint8List data) {
    final output = BytesBuilder(copy: false);
    for (var i = 0; i < data.length; i++) {
      output.addByte(data[i]);
      if (data[i] == 0xFF && i + 1 < data.length && data[i + 1] == 0x00) {
        i++;
      }
    }
    return output.takeBytes();
  }

  String? _normaliseGenre(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final match = RegExp(r'^\((\d{1,3})\)').firstMatch(trimmed);
    if (match != null) {
      final remainder = trimmed.substring(match.end).trim();
      if (remainder.isNotEmpty) return remainder;
      final index = int.tryParse(match.group(1)!);
      if (index != null && index < _id3Genres.length) return _id3Genres[index];
    }
    if (RegExp(r'^\d{1,3}$').hasMatch(trimmed)) {
      final index = int.tryParse(trimmed);
      if (index != null && index < _id3Genres.length) return _id3Genres[index];
    }
    return trimmed;
  }

  int? _parseYear(String? value) {
    if (value == null) return null;
    final match = RegExp(r'(\d{4})').firstMatch(value);
    if (match == null) return null;
    final year = int.tryParse(match.group(1)!);
    if (year == null || year < 1000 || year > 3000) return null;
    return year;
  }

  int? _parseLeadingNumber(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^\s*(\d+)').firstMatch(value);
    if (match == null) return null;
    final number = int.tryParse(match.group(1)!);
    if (number == null || number <= 0) return null;
    return number;
  }

  String? _cleanTagText(String? value) {
    if (value == null) return null;
    final trimmed = value.replaceAll('\u0000', '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _sniffImageMime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
