import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nm_vibe/core/storage/app_storage.dart';
import 'package:nm_vibe/data/models/download_record.dart';
import 'package:path/path.dart' as p;

class DownloadStorage {
  DownloadStorage({
    this.rootDirectoryOverride,
    Future<void> Function(File file, String contents)? writeTemporary,
    Future<File> Function(File source, String targetPath)? renameFile,
  }) : _writeTemporary = writeTemporary ?? _writeAndFlush,
       _renameFile = renameFile ?? _rename;

  final Directory? rootDirectoryOverride;
  final Future<void> Function(File file, String contents) _writeTemporary;
  final Future<File> Function(File source, String targetPath) _renameFile;
  Future<void> _operationTail = Future<void>.value();

  static Future<void> _writeAndFlush(File file, String contents) =>
      file.writeAsString(contents, flush: true);

  static Future<File> _rename(File source, String targetPath) =>
      source.rename(targetPath);

  Future<Directory> get root async {
    if (rootDirectoryOverride != null) {
      await rootDirectoryOverride!.create(recursive: true);
      return rootDirectoryOverride!;
    }
    final directory = Directory(
      p.join((await AppStorage.supportDirectory()).path, 'downloads'),
    );
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
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && !entity.path.endsWith('.part')) {
        size += await entity.length();
      }
    }
    return size;
  }

  Future<List<DownloadRecord>> records() => _serialized(() async {
    final directory = await root;
    await _recoverInterruptedWrite(directory);
    final file = _recordsFile(directory);
    if (!await file.exists()) return const [];
    try {
      return await _readRecords(file);
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  });

  Future<void> saveRecord(DownloadRecord record) =>
      _serialized(() => _saveRecord(record));

  Future<DownloadRecord?> deleteRecord(String recordId) =>
      _serialized(() => _deleteRecord(recordId));

  Future<DownloadRecord?> _deleteRecord(String recordId) async {
    final directory = await root;
    await _recoverInterruptedWrite(directory);
    final target = _recordsFile(directory);
    final records = await _readCurrentRecords(target);
    DownloadRecord? removed;
    final remaining = <DownloadRecord>[];
    for (final record in records) {
      if (record.id == recordId) {
        removed ??= record;
      } else {
        remaining.add(record);
      }
    }
    if (removed == null) return null;

    await _replaceRecords(directory, remaining);
    final file = File(removed.localPath);
    if (!await _isManagedFile(file, directory)) return removed;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Restore the index entry if a file lock prevented removal.
      await _saveRecord(removed);
      rethrow;
    }
    return removed;
  }

  Future<bool> _isManagedFile(File file, Directory downloadRoot) async {
    try {
      if (!await file.exists()) return false;
      final resolvedRoot = await downloadRoot.resolveSymbolicLinks();
      final resolvedFile = await file.resolveSymbolicLinks();
      return p.isWithin(resolvedRoot, resolvedFile);
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _saveRecord(DownloadRecord record) async {
    final directory = await root;
    await _recoverInterruptedWrite(directory);
    final target = _recordsFile(directory);
    final items = await _readCurrentRecords(target);
    final updated = <DownloadRecord>[
      for (final item in items)
        if (item.id != record.id) item,
      record,
    ];
    await _validateCompletedRecord(record);
    await _replaceRecords(directory, updated);
  }

  Future<void> _replaceRecords(
    Directory directory,
    List<DownloadRecord> updated,
  ) async {
    final target = _recordsFile(directory);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    final encoded = jsonEncode(updated.map((item) => item.toMap()).toList());
    try {
      await _writeTemporary(temporary, encoded);
      final staged = await _readRecords(temporary);
      if (!_sameRecords(staged, updated)) {
        throw const FormatException('The staged download index is incomplete.');
      }

      if (await target.exists()) {
        await target.copy(backup.path);
        await _readRecords(backup);
        await target.delete();
      }

      await _renameFile(temporary, target.path);
      final committed = await _readRecords(target);
      if (!_sameRecords(committed, updated)) {
        throw const FormatException(
          'The replacement download index is incomplete.',
        );
      }
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      await _restoreBackup(target, backup);
      rethrow;
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } on FileSystemException {
          // A stale temporary file is ignored and cleaned on the next write.
        }
      }
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        result.complete(await operation());
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  File _recordsFile(Directory directory) =>
      File(p.join(directory.path, 'download_records.json'));

  Future<List<DownloadRecord>> _readCurrentRecords(File file) async {
    if (!await file.exists()) return const [];
    return _readRecords(file);
  }

  Future<List<DownloadRecord>> _readRecords(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      throw const FormatException('The download index must contain a list.');
    }
    final records = <DownloadRecord>[];
    for (final item in decoded) {
      if (item is! Map) {
        throw const FormatException(
          'The download index contains an incomplete record.',
        );
      }
      final record = DownloadRecord.fromMap(Map<String, Object?>.from(item));
      if (record.localPath.trim().isEmpty ||
          record.localPath.toLowerCase().endsWith('.part') ||
          record.sizeBytes <= 0) {
        throw const FormatException(
          'The download index contains an incomplete record.',
        );
      }
      records.add(record);
    }
    return records;
  }

  bool _sameRecords(
    List<DownloadRecord> actual,
    List<DownloadRecord> expected,
  ) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (jsonEncode(actual[index].toMap()) !=
          jsonEncode(expected[index].toMap())) {
        return false;
      }
    }
    return true;
  }

  Future<void> _validateCompletedRecord(DownloadRecord record) async {
    if (record.localPath.trim().isEmpty ||
        record.localPath.toLowerCase().endsWith('.part') ||
        record.sizeBytes <= 0) {
      throw const FormatException('Only completed downloads can be indexed.');
    }
    final file = File(record.localPath);
    if (!await file.exists() || await file.length() != record.sizeBytes) {
      throw const FileSystemException(
        'The completed download is missing or incomplete.',
      );
    }
  }

  Future<void> _recoverInterruptedWrite(Directory directory) async {
    final target = _recordsFile(directory);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    final targetIsValid = await _isValidIndex(target);
    if (targetIsValid) {
      if (await backup.exists()) await backup.delete();
      await _deleteStaleTemporary(temporary);
      return;
    }
    if (await _isValidIndex(backup)) {
      if (await target.exists()) await target.delete();
      await _renameFile(backup, target.path);
      await _readRecords(target);
    }
    await _deleteStaleTemporary(temporary);
  }

  Future<bool> _isValidIndex(File file) async {
    if (!await file.exists()) return false;
    try {
      await _readRecords(file);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _restoreBackup(File target, File backup) async {
    if (!await _isValidIndex(backup)) return;
    if (await target.exists() && await _isValidIndex(target)) return;
    if (await target.exists()) await target.delete();
    try {
      await _renameFile(backup, target.path);
      await _readRecords(target);
    } on Object {
      // Keep the backup in place if restoration cannot be confirmed.
    }
  }

  Future<void> _deleteStaleTemporary(File temporary) async {
    if (!await temporary.exists()) return;
    try {
      await temporary.delete();
    } on FileSystemException {
      // A locked temporary file is left for a later cleanup attempt.
    }
  }

  Future<void> deleteAll() async {
    final directory = await root;
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  static Future<void> cleanupPartialFiles({Directory? rootDirectory}) async {
    final directory =
        rootDirectory ??
        Directory(
          p.join((await AppStorage.supportDirectory()).path, 'downloads'),
        );
    if (!await directory.exists()) return;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File && entity.path.endsWith('.part')) {
        try {
          await entity.delete();
        } on FileSystemException {
          // A currently locked temporary file is left for the next startup.
        }
      }
    }
    final storage = DownloadStorage(rootDirectoryOverride: directory);
    try {
      await storage._recoverInterruptedWrite(directory);
    } on FileSystemException {
      // Keep the backup so records() or the next write can retry recovery.
    }
  }
}
