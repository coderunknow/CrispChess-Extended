// File-backed benchmark storage (Android, iOS, desktop).
//
// One document per key, written to a temporary file and renamed into place, so
// a crash mid-write cannot leave half a run behind: the previous version stays
// readable and is also kept as `.bak` for the corruption-recovery path.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'benchmark_storage_base.dart';

/// Storage in the application support directory.
class FileBenchmarkStorage implements BenchmarkStorage {
  /// Subdirectory under application support.
  final String directoryName;

  /// Directory to use instead of application support.
  ///
  /// The atomic-write, `.bak` and key-sanitising rules are the part of this
  /// class that can lose a history, and none of them needs a Flutter plugin to
  /// exercise: a test gives the class a temporary directory and drives it like
  /// a real device would.
  final Directory? rootOverride;

  Directory? _root;

  FileBenchmarkStorage({this.directoryName = 'benchmark', this.rootOverride});

  @override
  Future<void> init() async {
    await _directory();
  }

  Future<Directory> _directory() async {
    final existing = _root;
    if (existing != null) return existing;
    final override = rootOverride;
    if (override != null) {
      // The override stands in for application support, so the documents still
      // live under their own subdirectory.
      final directory = Directory('${override.path}/$directoryName');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      _root = directory;
      return directory;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/$directoryName');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _root = directory;
    return directory;
  }

  /// Keys are used as file names, so anything that could escape the directory
  /// is rejected rather than sanitised into a different key.
  File _fileFor(Directory root, String key) {
    if (key.isEmpty ||
        key.contains('/') ||
        key.contains('\\') ||
        key.contains('..')) {
      throw ArgumentError.value(key, 'key', 'not a valid storage key');
    }
    return File('${root.path}/$key.json');
  }

  @override
  Future<String?> read(String key) async {
    final root = await _directory();
    final file = _fileFor(root, key);
    try {
      if (await file.exists()) return await file.readAsString();
      // A missing primary is the documented result of a crash between the two
      // renames in [write]: the recovery copy is then the newest data there is.
      return await readBackup(key);
    } catch (error) {
      // Unreadable is not fatal: the caller reports the run as corrupt and the
      // rest of the history still loads.
      return null;
    }
  }

  @override
  Future<String?> readBackup(String key) async {
    final root = await _directory();
    final backup = File('${_fileFor(root, key).path}.bak');
    try {
      if (!await backup.exists()) return null;
      return await backup.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final root = await _directory();
    final file = _fileFor(root, key);
    final temporary = File('${file.path}.tmp');
    // Flush the complete new document before anything replaces the old one: a
    // crash can then cost the newest save, never the previous good one.
    await temporary.writeAsString(value, flush: true);
    if (await file.exists()) {
      final backup = File('${file.path}.bak');
      try {
        if (await backup.exists()) await backup.delete();
        await file.copy(backup.path);
      } catch (_) {
        // A failed backup must not block the write that follows.
      }
    }
    await temporary.rename(file.path);
  }

  @override
  Future<void> restore(String key, String value) async {
    final root = await _directory();
    final file = _fileFor(root, key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String key) async {
    final root = await _directory();
    final file = _fileFor(root, key);
    for (final path in [file.path, '${file.path}.bak']) {
      final candidate = File(path);
      try {
        if (await candidate.exists()) await candidate.delete();
      } catch (_) {
        // Leaving a stale file behind is preferable to failing a delete.
      }
    }
  }

  @override
  Future<List<String>> keys(String prefix) async {
    final root = await _directory();
    try {
      final entries = await root.list().toList();
      return [
        for (final entry in entries)
          if (entry is File && entry.path.endsWith('.json'))
            if (_keyOf(entry).startsWith(prefix)) _keyOf(entry)
      ]..sort();
    } catch (_) {
      return const [];
    }
  }

  String _keyOf(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    return name.endsWith('.json')
        ? name.substring(0, name.length - '.json'.length)
        : name;
  }
}

/// The storage this platform uses.
BenchmarkStorage createDefaultBenchmarkStorage() => FileBenchmarkStorage();
