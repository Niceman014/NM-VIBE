import 'dart:io';

import 'package:nm_vibe/data/downloads/download_storage.dart';
import 'package:nm_vibe/data/models/download_record.dart';

enum OfflineFileAvailability { available, missing, sizeMismatch }

class OfflineTrackEntry {
  const OfflineTrackEntry({
    required this.record,
    required this.availability,
    required this.actualSizeBytes,
  });

  final DownloadRecord record;
  final OfflineFileAvailability availability;
  final int? actualSizeBytes;

  bool get canPlayOffline => availability == OfflineFileAvailability.available;
}

/// Reconciles saved download metadata with the files present on disk.
class OfflineIndex {
  const OfflineIndex(this._storage);

  final DownloadStorage _storage;

  Future<List<OfflineTrackEntry>> read() async {
    final records = await _storage.records();
    final entries = <OfflineTrackEntry>[];
    for (final record in records) {
      final file = File(record.localPath);
      if (!await file.exists()) {
        entries.add(
          OfflineTrackEntry(
            record: record,
            availability: OfflineFileAvailability.missing,
            actualSizeBytes: null,
          ),
        );
        continue;
      }
      final actualSize = await file.length();
      entries.add(
        OfflineTrackEntry(
          record: record,
          availability: actualSize == record.sizeBytes
              ? OfflineFileAvailability.available
              : OfflineFileAvailability.sizeMismatch,
          actualSizeBytes: actualSize,
        ),
      );
    }
    return List<OfflineTrackEntry>.unmodifiable(entries);
  }
}
