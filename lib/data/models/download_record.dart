class DownloadRecord {
  const DownloadRecord({
    required this.id,
    required this.source,
    required this.localPath,
    required this.codec,
    required this.bitrateKbps,
    required this.license,
    required this.downloadedAt,
    required this.sizeBytes,
  });

  final String id;
  final String source;
  final String localPath;
  final String codec;
  final int? bitrateKbps;
  final String license;
  final DateTime downloadedAt;
  final int sizeBytes;

  Map<String, Object?> toMap() => {
    'id': id,
    'source': source,
    'localPath': localPath,
    'codec': codec,
    'bitrateKbps': bitrateKbps,
    'license': license,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
    'sizeBytes': sizeBytes,
  };

  factory DownloadRecord.fromMap(Map<String, Object?> map) => DownloadRecord(
    id: map['id'] as String,
    source: map['source'] as String,
    localPath: map['localPath'] as String,
    codec: map['codec'] as String,
    bitrateKbps: map['bitrateKbps'] as int?,
    license: map['license'] as String,
    downloadedAt: DateTime.parse(map['downloadedAt'] as String),
    sizeBytes: map['sizeBytes'] as int,
  );
}
