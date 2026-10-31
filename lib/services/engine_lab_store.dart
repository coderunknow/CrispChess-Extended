import 'dart:async';
import 'dart:convert';

import 'engine_lab_models.dart';
import 'engine_lab_storage.dart' as storage;

class EngineLabCorruptHistoryException implements Exception {
  final String message;
  const EngineLabCorruptHistoryException(this.message);
  @override
  String toString() => message;
}

/// Local-first, versioned benchmark history store. Native platforms write a
/// flushed application-support JSON snapshot with a recoverable backup; Web
/// uses browser local storage via shared_preferences (subject to browser quota).
/// Mutations re-read and write a full validated snapshot to prevent lost updates.
class EngineLabStore {
  static Future<void> _writeTail = Future<void>.value();
  final Future<String?> Function() _read;
  final Future<String?> Function() _readBackup;
  final Future<void> Function(String value) _write;
  bool recoveredFromBackup = false;

  EngineLabStore({
    Future<String?> Function()? read,
    Future<String?> Function()? readBackup,
    Future<void> Function(String value)? write,
  })  : _read = read ?? storage.readEngineLabData,
        _readBackup = readBackup ?? storage.readEngineLabBackup,
        _write = write ?? storage.writeEngineLabData;

  Future<List<EngineBenchmarkRun>> load() async {
    final primary = await _read();
    if (primary == null || primary.isEmpty) return [];
    try {
      return _decode(primary);
    } catch (primaryError) {
      final backup = await _readBackup();
      if (backup != null && backup.isNotEmpty) {
        try {
          final runs = _decode(backup);
          recoveredFromBackup = true;
          await _write(_encode(runs));
          return runs;
        } catch (backupError) {
          throw EngineLabCorruptHistoryException(
            'Benchmark history and recovery snapshot are unreadable. '
            'Primary: $primaryError; backup: $backupError',
          );
        }
      }
      throw EngineLabCorruptHistoryException(
        'Benchmark history is unreadable and no recovery snapshot exists: $primaryError',
      );
    }
  }

  Future<void> addRun(EngineBenchmarkRun run) => _enqueue(() async {
        final runs = await _loadForMutation();
        if (runs.any((existing) => existing.id == run.id)) {
          throw ArgumentError.value(run.id, 'run.id', 'already exists');
        }
        runs.add(run);
        await _write(_encode(runs));
      });

  /// Import is additive and transactional. Existing identifiers are never
  /// replaced; malformed reports abort the whole import before any write.
  Future<int> importJson(String input) => _enqueue(() async {
        final imported = _decodeImport(input);
        final existing = await _loadForMutation();
        final ids = existing.map((run) => run.id).toSet();
        for (final run in imported) {
          if (!ids.add(run.id)) {
            throw ArgumentError('Import contains an existing or duplicate run id: ${run.id}');
          }
        }
        await _write(_encode([...existing, ...imported]));
        return imported.length;
      });

  Future<String> exportJson() async => _encode(await load());

  Future<List<EngineBenchmarkRun>> _loadForMutation() async {
    try {
      return await load();
    } on EngineLabCorruptHistoryException {
      // Never overwrite the only recoverable copy on corrupt data.
      rethrow;
    }
  }

  List<EngineBenchmarkRun> _decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> || value['schemaVersion'] != engineLabSchemaVersion || value['runs'] is! List) {
      throw const FormatException('Invalid benchmark history envelope or schema version');
    }
    final runs = (value['runs'] as List)
        .map((entry) {
          if (entry is! Map) throw const FormatException('Benchmark report must be an object');
          return EngineBenchmarkRun.fromJson(Map<String, dynamic>.from(entry));
        })
        .toList();
    final ids = <String>{};
    for (final run in runs) {
      if (!ids.add(run.id)) throw FormatException('Duplicate report id ${run.id}');
    }
    return runs;
  }

  List<EngineBenchmarkRun> _decodeImport(String input) {
    final value = jsonDecode(input);
    if (value is List) {
      return value.map((entry) {
        if (entry is! Map) throw const FormatException('Each imported report must be an object');
        return EngineBenchmarkRun.fromJson(Map<String, dynamic>.from(entry));
      }).toList();
    }
    if (value is Map<String, dynamic> && value['runs'] is List) {
      return _decode(input);
    }
    if (value is Map<String, dynamic>) return [EngineBenchmarkRun.fromJson(value)];
    throw const FormatException('Expected a benchmark report or report collection');
  }

  String _encode(List<EngineBenchmarkRun> runs) => const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': engineLabSchemaVersion,
        'runs': runs.map((run) => run.toJson()).toList(),
      });

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeTail = _writeTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }
}
