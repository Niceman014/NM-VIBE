import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nm_vibe/data/downloads/download_storage.dart';
import 'package:nm_vibe/data/models/download_record.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporaryDirectory;
  late Directory downloadsDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('nmvibe_index_');
    downloadsDirectory = Directory(
      p.join(temporaryDirectory.path, 'downloads'),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'successfully replaces the index and retains unrelated records',
    () async {
      final storage = DownloadStorage(
        rootDirectoryOverride: downloadsDirectory,
      );
      final first = await _writeCompletedFile(downloadsDirectory, 'first.mp3', [
        1,
        2,
      ]);
      final second = await _writeCompletedFile(
        downloadsDirectory,
        'second.mp3',
        [3, 4, 5],
      );
      await storage.saveRecord(_record('first', first.path, 2));
      await storage.saveRecord(_record('second', second.path, 3));

      final records = await storage.records();

      expect(records.map((record) => record.id), ['first', 'second']);
      expect(
        await File(p.join(downloadsDirectory.path, 'download_records.json.bak'))
            .exists(),
        isFalse,
      );
      expect(
        await File(p.join(downloadsDirectory.path, 'download_records.json.tmp'))
            .exists(),
        isFalse,
      );
    },
  );

  test('temporary write failure preserves the previous index', () async {
    final initialStorage = DownloadStorage(
      rootDirectoryOverride: downloadsDirectory,
    );
    final originalFile = await _writeCompletedFile(
      downloadsDirectory,
      'original.mp3',
      [1],
    );
    final nextFile = await _writeCompletedFile(downloadsDirectory, 'next.mp3', [
      2,
      3,
    ]);
    await initialStorage.saveRecord(_record('original', originalFile.path, 1));
    final failingStorage = DownloadStorage(
      rootDirectoryOverride: downloadsDirectory,
      writeTemporary: (_, _) async =>
          throw const FileSystemException('write failed'),
    );

    await expectLater(
      failingStorage.saveRecord(_record('next', nextFile.path, 2)),
      throwsA(isA<FileSystemException>()),
    );
    expect((await initialStorage.records()).map((record) => record.id), [
      'original',
    ]);
  });

  test('invalid staged JSON does not replace the previous index', () async {
    final initialStorage = DownloadStorage(
      rootDirectoryOverride: downloadsDirectory,
    );
    final originalFile = await _writeCompletedFile(
      downloadsDirectory,
      'original.mp3',
      [1],
    );
    final nextFile = await _writeCompletedFile(downloadsDirectory, 'next.mp3', [
      2,
    ]);
    await initialStorage.saveRecord(_record('original', originalFile.path, 1));
    final invalidStagingStorage = DownloadStorage(
      rootDirectoryOverride: downloadsDirectory,
      writeTemporary: (file, _) =>
          file.writeAsString('not valid json', flush: true),
    );

    await expectLater(
      invalidStagingStorage.saveRecord(_record('next', nextFile.path, 1)),
      throwsA(isA<FormatException>()),
    );
    expect((await initialStorage.records()).map((record) => record.id), [
      'original',
    ]);
  });

  test('rename failure restores the previous valid index', () async {
    final initialStorage = DownloadStorage(
      rootDirectoryOverride: downloadsDirectory,
    );
    final originalFile = await _writeCompletedFile(
      downloadsDirectory,
      'original.mp3',
      [1],
    );
    final nextFile = await _writeCompletedFile(downloadsDirectory, 'next.mp3', [
      2,
    ]);
    await initialStorage.saveRecord(_record('original', originalFile.path, 1));
    var failFirstRename = true;
    final failingRenameStorage = DownloadStorage(
      rootDirectoryOverride: downloadsDirectory,
      renameFile: (source, targetPath) async {
        if (failFirstRename) {
          failFirstRename = false;
          throw const FileSystemException('rename failed');
        }
        return source.rename(targetPath);
      },
    );

    await expectLater(
      failingRenameStorage.saveRecord(_record('next', nextFile.path, 1)),
      throwsA(isA<FileSystemException>()),
    );
    expect((await initialStorage.records()).map((record) => record.id), [
      'original',
    ]);
  });

  test(
    'restart restores a valid backup and discards interrupted temp data',
    () async {
      await downloadsDirectory.create(recursive: true);
      final originalFile = await _writeCompletedFile(
        downloadsDirectory,
        'original.mp3',
        [1, 2],
      );
      final record = _record('original', originalFile.path, 2);
      final target = File(
        p.join(downloadsDirectory.path, 'download_records.json'),
      );
      await File('${target.path}.bak')
          .writeAsString(jsonEncode([record.toMap()]));
      await File('${target.path}.tmp').writeAsString('[{"unfinished":');

      await DownloadStorage.cleanupPartialFiles(
        rootDirectory: downloadsDirectory,
      );
      final records = await DownloadStorage(
        rootDirectoryOverride: downloadsDirectory,
      ).records();

      expect(records.map((item) => item.id), ['original']);
      expect(await target.exists(), isTrue);
      expect(await File('${target.path}.tmp').exists(), isFalse);
      expect(await File('${target.path}.bak').exists(), isFalse);
    },
  );

  test(
    'does not index a partial or size-mismatched file as complete',
    () async {
      final storage = DownloadStorage(
        rootDirectoryOverride: downloadsDirectory,
      );
      final partial = await _writeCompletedFile(
        downloadsDirectory,
        'unfinished.part',
        [1, 2],
      );
      final mismatch = await _writeCompletedFile(
        downloadsDirectory,
        'mismatch.mp3',
        [1, 2],
      );

      await expectLater(
        storage.saveRecord(_record('partial', partial.path, 2)),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        storage.saveRecord(_record('mismatch', mismatch.path, 3)),
        throwsA(isA<FileSystemException>()),
      );
      expect(await storage.records(), isEmpty);
    },
  );

  test('deleteRecord removes only the selected file and index row', () async {
    final storage = DownloadStorage(rootDirectoryOverride: downloadsDirectory);
    final firstFile = await _writeCompletedFile(
      downloadsDirectory,
      'first.mp3',
      [1, 2],
    );
    final keepFile = await _writeCompletedFile(downloadsDirectory, 'keep.mp3', [
      3,
      4,
    ]);
    await storage.saveRecord(_record('first', firstFile.path, 2));
    await storage.saveRecord(_record('keep', keepFile.path, 2));

    final removed = await storage.deleteRecord('first');

    expect(removed?.id, 'first');
    expect(await firstFile.exists(), isFalse);
    expect(await keepFile.exists(), isTrue);
    expect((await storage.records()).map((record) => record.id), ['keep']);
  });

  test(
    'deleteRecord never removes a file outside managed download storage',
    () async {
      final storage = DownloadStorage(
        rootDirectoryOverride: downloadsDirectory,
      );
      final sourceFile = await _writeCompletedFile(
        temporaryDirectory,
        'original-source.mp3',
        [7, 8, 9],
      );
      await storage.saveRecord(_record('misdirected', sourceFile.path, 3));

      final removed = await storage.deleteRecord('misdirected');

      expect(removed?.id, 'misdirected');
      expect(await sourceFile.exists(), isTrue);
      expect(await storage.records(), isEmpty);
    },
  );
}

Future<File> _writeCompletedFile(
  Directory directory,
  String name,
  List<int> bytes,
) async {
  final file = File(p.join(directory.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  return file;
}

DownloadRecord _record(String id, String path, int size) => DownloadRecord(
  id: id,
  source: 'internet_archive',
  localPath: path,
  codec: 'MP3',
  bitrateKbps: 128,
  license: 'CC0',
  downloadedAt: DateTime.utc(2026),
  sizeBytes: size,
);
