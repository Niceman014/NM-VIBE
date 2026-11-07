import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/downloads/download_storage.dart';
import 'package:nm_vibe/data/downloads/offline_index.dart';
import 'package:nm_vibe/data/models/download_record.dart';

void main() {
  test(
    'reports available, missing, and size-mismatched offline files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'nm_vibe_offline_index_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final root = Directory(
        '${directory.path}${Platform.pathSeparator}downloads',
      );
      final storage = DownloadStorage(rootDirectoryOverride: root);
      final sourceDirectory = await storage.sourceDirectory('internet_archive');

      final available = File(
        '${sourceDirectory.path}${Platform.pathSeparator}available.mp3',
      );
      final missing = File(
        '${sourceDirectory.path}${Platform.pathSeparator}missing.mp3',
      );
      final changed = File(
        '${sourceDirectory.path}${Platform.pathSeparator}changed.mp3',
      );
      await available.writeAsBytes([1, 2]);
      await missing.writeAsBytes([3, 4]);
      await changed.writeAsBytes([5, 6, 7]);

      await storage.saveRecord(_record('available', available.path, 2));
      await storage.saveRecord(_record('missing', missing.path, 2));
      await storage.saveRecord(_record('changed', changed.path, 3));
      await missing.delete();
      await changed.writeAsBytes([5, 6]);

      final entries = await OfflineIndex(storage).read();

      expect(entries.map((entry) => entry.availability), [
        OfflineFileAvailability.available,
        OfflineFileAvailability.missing,
        OfflineFileAvailability.sizeMismatch,
      ]);
      expect(entries.first.canPlayOffline, isTrue);
      expect(entries[1].canPlayOffline, isFalse);
      expect(entries[2].actualSizeBytes, 2);
    },
  );
}

DownloadRecord _record(String id, String localPath, int sizeBytes) =>
    DownloadRecord(
      id: 'internet_archive:$id',
      source: 'internet_archive',
      localPath: localPath,
      codec: 'MP3',
      bitrateKbps: 128,
      license: 'CC0',
      downloadedAt: DateTime.utc(2026),
      sizeBytes: sizeBytes,
    );
