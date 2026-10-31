import 'dart:convert';
import 'dart:io';

import 'package:nm_vibe/core/storage/app_storage.dart';
import 'package:nm_vibe/data/models/download_record.dart';
import 'package:path/path.dart' as p;

class DownloadStorage {
  DownloadStorage({this.rootDirectoryOverride});

  final Directory? rootDirectoryOverride;

  Future<Directory> get root async {
    if (rootDirectoryOverride != null) {
      await rootDirectoryOverride!.create(recursive: true);
      return rootDirectoryOverride!;
    }
    final directory = Directory(p.join(
      (await AppStorage.supportDirectory()).path,
      'downloads',
    ));
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> sourceDirectory(String source) async {
    final directory = Directory(p.join((await root).path, source));
    await directory.create(recursive: true);
    return directory;
  }

  Future<int> sizeBytes() async {
    final directory = await root;
    var size = 0;
    if (!await directory.exists()) return 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && !entity.path.endsWith('.part')) {
        size += await entity.length();
      }
    }
    return size;
  }

  Future<List<DownloadRecord>> records() async {
    final file = File(p.join((await root).path, 'download_records.json'));
    if (!await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DownloadRecord.fromMap(Map<String, Object?>.from(item)))
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  Future<void> saveRecord(DownloadRecord record) async {
    final directory = await root;
    final items = await records();
    final updated = <DownloadRecord>[
      for (final item in items)
        if (item.id != record.id) item,
      record,
    ];
    final target = File(p.join(directory.path, 'download_records.json'));
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(updated.map((item) => item.toMap()).toList()),
      flush: true,
    );
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }

  Future<void> deleteAll() async {
    final directory = await root;
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static Future<void> cleanupPartialFiles({Directory? rootDirectory}) async {
    final directory = rootDirectory ?? Directory(p.join(
      (await AppStorage.supportDirectory()).path,
      'downloads',
    ));
    if (!await directory.exists()) return;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.part')) {
        try {
          await entity.delete();
        } on FileSystemException {
          // A currently locked temporary file is left for the next startup.
        }
      }
    }
  }
}
