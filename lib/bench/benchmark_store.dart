/// Durable benchmark history.
///
/// One document per run plus a small index, both checksummed, both written
/// through [BenchmarkStorage]. The design goals, in order:
///
///  1. **Nothing is lost.** A run is written when it finishes and updated while
///     it runs, so closing the app mid-benchmark keeps the games already played.
///  2. **Corruption is contained.** A document whose checksum does not match is
///     moved aside (kept, not deleted) and reported; every other run still
///     loads.
///  3. **The schema can move forward.** Documents carry a schema version and
///     are migrated on read; a document from a *newer* version is refused with
///     a clear message rather than half-read.
///  4. **Import never overwrites.** Importing a run whose id already exists
///     stores it under a fresh id and says so.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show debugPrint;

import 'benchmark_environment.dart';
import 'benchmark_fingerprint.dart' show ExecutableStat, sha256OfFile, statExecutable;
import 'benchmark_run.dart';
import 'benchmark_storage.dart';
import 'engine_identity.dart';

/// Current schema of a stored run document.
const int kBenchmarkStoreSchema = 1;

/// Storage key for the run index.
const String kBenchmarkIndexKey = 'index';

/// Storage key for the last known engine identities.
const String kBenchmarkIdentitiesKey = 'identities';

/// Storage key for the executable fingerprint cache.
const String kBenchmarkFingerprintKey = 'fingerprints';

/// Prefix for run documents.
const String kBenchmarkRunPrefix = 'run__';

/// Prefix for quarantined documents.
const String kBenchmarkCorruptPrefix = 'corrupt__';

/// One stored run document, decoded or explained.
class _DecodedDocument {
  final BenchmarkRun? run;
  final String? reason;

  /// True when the document is intact but was written by a newer schema, which
  /// is a refusal rather than corruption.
  final bool futureSchema;

  const _DecodedDocument({this.run, this.reason, this.futureSchema = false});
}

/// A run document that could not be read.
class CorruptRun {
  final String key;
  final String reason;

  const CorruptRun({required this.key, required this.reason});

  /// The run id inside the key, when it can be recovered.
  String get runId => key.startsWith(kBenchmarkRunPrefix)
      ? key.substring(kBenchmarkRunPrefix.length)
      : key;
}

/// The result of an import.
class ImportResult {
  final BenchmarkRun run;

  /// True when the id in the document already existed and a new one was used.
  final bool idChanged;

  final List<String> warnings;

  const ImportResult({
    required this.run,
    this.idChanged = false,
    this.warnings = const [],
  });
}

/// Crash-safe cache entry for an executable fingerprint.
class _FingerprintEntry {
  final ExecutableStat stat;
  final String? sha256;

  const _FingerprintEntry(this.stat, this.sha256);
}

/// Reads and writes the benchmark history.
class BenchmarkStore {
  final BenchmarkStorage storage;

  BenchmarkStore({BenchmarkStorage? storage})
      : storage = storage ?? createDefaultBenchmarkStorage();

  bool _initialised = false;

  /// Serialises writes, so a background save cannot interleave with the save
  /// at the end of a run and lose the index update.
  Future<void> _writeChain = Future<void>.value();

  Future<void> init() async {
    if (_initialised) return;
    await storage.init();
    _initialised = true;
  }

  Future<T> _serialised<T>(Future<T> Function() action) {
    final gate = Completer<void>();
    final previous = _writeChain;
    _writeChain = gate.future;
    return previous.then((_) async {
      try {
        return await action();
      } finally {
        gate.complete();
      }
    });
  }

  // ---------------------------------------------------------------- run index

  /// Every stored run, newest first.
  Future<List<BenchmarkRunSummary>> summaries() async {
    await init();
    final raw = await storage.read(kBenchmarkIndexKey);
    if (raw == null || raw.isEmpty) return _rebuildIndex();
    List<BenchmarkRunSummary> summaries;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return _rebuildIndex();
      summaries = [
        for (final entry in decoded)
          if (entry is Map)
            BenchmarkRunSummary.fromJson(Map<String, dynamic>.from(entry)),
      ];
    } catch (_) {
      // A broken index is rebuilt from the run documents rather than losing the
      // runs it described.
      return _rebuildIndex();
    }
    summaries.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return summaries;
  }

  Future<List<BenchmarkRunSummary>> _rebuildIndex() async {
    final rebuilt = <BenchmarkRunSummary>[];
    for (final key in await storage.keys(kBenchmarkRunPrefix)) {
      final run = await _readRunKey(key);
      if (run != null) rebuilt.add(run.summary());
    }
    rebuilt.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    await _writeIndex(rebuilt);
    return rebuilt;
  }

  Future<void> _writeIndex(List<BenchmarkRunSummary> summaries) =>
      storage.write(
        kBenchmarkIndexKey,
        jsonEncode([for (final summary in summaries) summary.toJson()]),
      );

  // ------------------------------------------------------------------ saving

  /// Stores [run], replacing any run with the same id.
  Future<void> saveRun(BenchmarkRun run) => _serialised(() => _saveRun(run));

  Future<void> _saveRun(BenchmarkRun run) async {
        await init();
        await storage.write(
          '$kBenchmarkRunPrefix${run.id}',
          encodeRunDocument(run),
        );
        final summaries = await this.summaries();
        final summary = run.summary();
        final merged = [
          summary,
          for (final existing in summaries)
            if (existing.id != run.id) existing,
        ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        await _writeIndex(merged);
        await _rememberIdentities(run.engines);
      }

  /// The run document as it is stored, including schema and checksum.
  static String encodeRunDocument(BenchmarkRun run) {
    final payload = run.toJson();
    final checksum = _checksumOf(payload);
    return jsonEncode({
      'schema': kBenchmarkStoreSchema,
      'id': run.id,
      'checksum': checksum,
      'payload': payload,
    });
  }

  Future<void> _rememberIdentities(List<EngineIdentity> identities) async {
    if (identities.isEmpty) return;
    final known = await knownIdentities();
    for (final identity in identities) {
      // Only the most recent measurement of an engine matters for the
      // version-change trigger.
      known[identity.engineId] = identity;
    }
    await storage.write(
      kBenchmarkIdentitiesKey,
      jsonEncode({
        for (final entry in known.entries) entry.key: entry.value.toJson()
      }),
    );
  }

  /// The last identity each engine was benchmarked with.
  Future<Map<String, EngineIdentity>> knownIdentities() async {
    await init();
    final raw = await storage.read(kBenchmarkIdentitiesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, EngineIdentity>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          result['$key'] =
              EngineIdentity.fromJson(Map<String, dynamic>.from(value));
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  // ------------------------------------------------------------------ loading

  /// Loads a run, or null when it does not exist or had to be quarantined.
  Future<BenchmarkRun?> loadRun(String id) async {
    await init();
    return _readRunKey('$kBenchmarkRunPrefix$id');
  }

  /// Reads one run document, recovering a corrupt primary from the `.bak` copy.
  ///
  /// The order matters and used to be wrong: the primary was decoded, and on
  /// failure the store quarantined it — which deletes the key *and* its backup —
  /// so a corrupt update threw away the last valid copy that was sitting right
  /// next to it. Now a failed primary is archived, the recovery copy is tried,
  /// and only a run with no readable copy at all is dropped from the index.
  Future<BenchmarkRun?> _readRunKey(String key) async {
    final raw = await storage.read(key);
    String? failure;
    if (raw != null && raw.isNotEmpty) {
      final decoded = _decodeRunDocument(raw);
      if (decoded.run != null) return decoded.run;
      if (decoded.futureSchema) {
        // A newer build wrote this. Keep it exactly as it is: replacing it with
        // an older backup would downgrade the user's history.
        debugPrint('[BenchmarkStore] refusing $key: ${decoded.reason}');
        return null;
      }
      failure = decoded.reason;
      // Keep the bytes before anything overwrites them.
      await _archiveCorrupt(key, raw, decoded.reason ?? 'unreadable');
    }

    final backupRaw = await storage.readBackup(key);
    if (backupRaw != null && backupRaw.isNotEmpty) {
      final recovered = _decodeRunDocument(backupRaw);
      if (recovered.run != null) {
        // Put the good copy back where the next read expects it, so recovery
        // happens once instead of on every load.
        try {
          await storage.restore(key, backupRaw);
        } catch (error) {
          debugPrint('[BenchmarkStore] could not restore $key from backup: $error');
        }
        return recovered.run;
      }
      failure ??= 'primary missing, recovery copy unreadable: ${recovered.reason}';
    }

    if (raw == null || raw.isEmpty) {
      // Nothing was stored and nothing could be recovered: an absent run, not a
      // corrupt one.
      return null;
    }
    await _dropFromIndex(_idFromKey(key));
    await storage.delete(key);
    debugPrint('[BenchmarkStore] dropped $key: $failure');
    return null;
  }

  /// Decodes a stored document without touching storage, so a failure can be
  /// handled by the caller (recover from the backup, then quarantine).
  _DecodedDocument _decodeRunDocument(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const _DecodedDocument(reason: 'the document is not an object');
      }
      final document = Map<String, dynamic>.from(decoded);
      final payloadValue = document['payload'];
      if (payloadValue is! Map) {
        return const _DecodedDocument(reason: 'the document has no payload');
      }
      final payload = Map<String, dynamic>.from(payloadValue);

      final schema = document['schema'];
      final schemaVersion = schema is num ? schema.toInt() : 0;
      if (schemaVersion > kBenchmarkStoreSchema) {
        // Refuse rather than guess: reading a newer document with this build
        // could drop fields the newer build relies on. It is not corruption, so
        // it must not be archived *or* replaced by an older recovery copy.
        return _DecodedDocument(
          reason: 'written by a newer version of the app (schema $schemaVersion)',
          futureSchema: true,
        );
      }

      final expected = document['checksum'];
      if (expected is String && expected.isNotEmpty) {
        final actual = _checksumOf(payload);
        if (actual != expected) {
          return const _DecodedDocument(reason: 'checksum mismatch');
        }
      }

      final migrated = _migrate(payload, schemaVersion);
      return _DecodedDocument(run: BenchmarkRun.fromJson(migrated));
    } catch (error) {
      return _DecodedDocument(reason: 'unreadable: $error');
    }
  }

  /// Upgrades an older document in memory.
  ///
  /// Version 0 is "a document written before this schema existed": everything
  /// that was optional then is defaulted, and nothing is dropped.
  Map<String, dynamic> _migrate(Map<String, dynamic> payload, int schema) {
    if (schema >= kBenchmarkStoreSchema) return payload;
    final migrated = Map<String, dynamic>.from(payload);
    migrated['stopReason'] = migrated['stopReason'] ?? 'completed';
    migrated['format'] = migrated['format'] ?? 'roundRobin';
    if (migrated['ratings'] == null) {
      migrated['ratings'] = const <String, dynamic>{};
    }
    if (migrated['calibration'] == null) {
      migrated['calibration'] = const <String, dynamic>{
        'available': false,
        'reason': 'This run predates calibrated ratings.',
      };
    }
    if (migrated['environment'] == null) {
      migrated['environment'] = BenchmarkEnvironment.unknown.toJson();
    }
    if (migrated['engineStatus'] == null) {
      migrated['engineStatus'] = const <String, dynamic>{};
    }
    return migrated;
  }

  /// Keeps the bytes of a document that failed validation, under a key that
  /// says why. It never deletes the original: recovery and deletion are
  /// separate decisions made by the caller.
  Future<void> _archiveCorrupt(String key, String raw, String reason) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    try {
      await storage.write(
          '$kBenchmarkCorruptPrefix${stamp}__${_keySafeReason(reason)}', raw);
    } catch (error) {
      debugPrint('[BenchmarkStore] could not archive $key: $error');
    }
  }

  /// Removes a run from the index. The index is edited directly rather than
  /// through `summary()`: a corrupt index is one of the things that leads here,
  /// and going through the public path would rebuild it out of the document
  /// that just failed.
  Future<void> _dropFromIndex(String id) async {
    final indexRaw = await storage.read(kBenchmarkIndexKey);
    if (indexRaw == null || indexRaw.isEmpty) return;
    try {
      final decoded = jsonDecode(indexRaw);
      if (decoded is! List) return;
      final kept = <BenchmarkRunSummary>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final summary =
            BenchmarkRunSummary.fromJson(Map<String, dynamic>.from(entry));
        if (summary.id == id) continue;
        kept.add(summary);
      }
      await _writeIndex(kept);
    } catch (_) {
      // Leave the index alone; the next rebuild will drop the missing run.
    }
  }

  /// Keeps a reason readable but safe to use as a storage key.
  String _keySafeReason(String reason) {
    final cleaned = reason
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (cleaned.isEmpty) return 'unknown';
    return cleaned.length <= 32 ? cleaned : cleaned.substring(0, 32);
  }

  String _idFromKey(String key) => key.startsWith(kBenchmarkRunPrefix)
      ? key.substring(kBenchmarkRunPrefix.length)
      : key;

  /// Documents that had to be quarantined, newest first.
  Future<List<CorruptRun>> quarantined() async {
    await init();
    final keys = await storage.keys(kBenchmarkCorruptPrefix);
    return [
      for (final key in keys.reversed)
        CorruptRun(
          key: key,
          reason: key.contains('__')
              ? key.substring(key.indexOf('__') + 2)
              : 'unknown',
        )
    ];
  }

  /// Deletes a run and its index entry.
  Future<bool> deleteRun(String id) => _serialised(() async {
        await init();
        final raw = await storage.read('$kBenchmarkRunPrefix$id');
        if (raw == null) return false;
        await storage.delete('$kBenchmarkRunPrefix$id');
        final summaries = await this.summaries();
        await _writeIndex([
          for (final summary in summaries)
            if (summary.id != id) summary
        ]);
        return true;
      });

  // ------------------------------------------------------------------ export

  /// The stored JSON of one run, for sharing.
  Future<String?> exportRunJson(String id) async {
    final run = await loadRun(id);
    if (run == null) return null;
    return encodeRunDocument(run);
  }

  /// Every run in one document, for a full backup.
  Future<String> exportAllJson() async {
    final summaries = await this.summaries();
    final documents = <Map<String, dynamic>>[];
    for (final summary in summaries) {
      final run = await loadRun(summary.id);
      if (run == null) continue;
      documents.add({
        'schema': kBenchmarkStoreSchema,
        'id': run.id,
        'checksum': _checksumOf(run.toJson()),
        'payload': run.toJson(),
      });
    }
    return jsonEncode({
      'format': 'crispchess-benchmark-backup',
      'schema': kBenchmarkStoreSchema,
      'exportedAt': DateTime.now().toIso8601String(),
      'runs': documents,
    });
  }

  // ------------------------------------------------------------------ import

  /// Imports a run (or a full backup) from [text].
  ///
  /// Never overwrites: a run whose id is already stored gets a new id, and the
  /// caller is told so.
  Future<List<ImportResult>> importJson(String text) => _serialised(() async {
    await init();
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw FormatException('That is not valid JSON: ${error.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('Expected a benchmark document.');
    }
    final document = Map<String, dynamic>.from(decoded);
    final runs = <Map<String, dynamic>>[];
    if (document['format'] == 'crispchess-benchmark-backup') {
      final rawRuns = document['runs'];
      if (rawRuns is! List) {
        throw const FormatException('The backup contains no runs.');
      }
      for (final entry in rawRuns) {
        if (entry is Map) runs.add(Map<String, dynamic>.from(entry));
      }
    } else if (document.containsKey('payload')) {
      runs.add(document);
    } else if (document.containsKey('games') && document.containsKey('id')) {
      // A bare run payload, as exported by an older build or hand-written.
      runs.add({
        'schema': kBenchmarkStoreSchema,
        'payload': document,
      });
    } else {
      throw const FormatException(
          'Expected a run document or a benchmark backup.');
    }
    if (runs.isEmpty) {
      throw const FormatException('No runs found in that document.');
    }

    final results = <ImportResult>[];
    for (final entry in runs) {
      final payloadValue = entry['payload'];
      if (payloadValue is! Map) {
        throw const FormatException('A run in that document has no payload.');
      }
      final payload = Map<String, dynamic>.from(payloadValue);
      final schema = entry['schema'];
      final schemaVersion = schema is num ? schema.toInt() : 0;
      if (schemaVersion > kBenchmarkStoreSchema) {
        throw FormatException(
            'That document was written by a newer version (schema '
            '$schemaVersion, this build understands $kBenchmarkStoreSchema).');
      }
      final warnings = <String>[];
      final checksum = entry['checksum'];
      if (checksum is String && checksum.isNotEmpty) {
        final actual = _checksumOf(payload);
        if (actual != checksum) {
          warnings.add('Checksum mismatch: this run was edited or damaged '
              'after export. Imported as-is.');
        }
      }
      if (!payload.containsKey('games') || payload['games'] is! List) {
        throw const FormatException('A run in that document has no games.');
      }

      final parsed = BenchmarkRun.fromJson(_migrate(payload, schemaVersion));
      // Existence, not successful decoding: a future-schema document belongs
      // to the user too and must not be downgraded by an import.
      final existing = await storage.read('$kBenchmarkRunPrefix${parsed.id}') ??
          await storage.readBackup('$kBenchmarkRunPrefix${parsed.id}');
      var idChanged = false;
      var run = parsed;
      if (existing != null) {
        idChanged = true;
        var attempt = 0;
        do {
          run = _withNewId(parsed, attempt++);
        } while (await storage.read('$kBenchmarkRunPrefix${run.id}') != null ||
            await storage.readBackup('$kBenchmarkRunPrefix${run.id}') != null);
        warnings.add('A run with id ${parsed.id} already exists; imported as '
            '${run.id} instead of overwriting it.');
      }
      await _saveRun(run);
      results.add(ImportResult(run: run, idChanged: idChanged, warnings: warnings));
    }
    return results;
  });

  BenchmarkRun _withNewId(BenchmarkRun run, int attempt) {
    final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return BenchmarkRun(
      id: '${run.id}-import-$suffix-$attempt',
      startedAt: run.startedAt,
      finishedAt: run.finishedAt,
      config: run.config,
      format: run.format,
      engines: run.engines,
      engineStatus: run.engineStatus,
      games: run.games,
      ratings: run.ratings,
      calibration: run.calibration,
      environment: run.environment,
      stopReason: run.stopReason,
      warnings: run.warnings,
      validationWarnings: run.validationWarnings,
      trigger: run.trigger,
    );
  }

  // -------------------------------------------------------------- fingerprints

  /// SHA-256 for a user-added engine, from the cache when the file has not
  /// changed.
  ///
  /// The cache key is the profile id; the entry is only reused when size and
  /// modification time match, so editing or replacing a binary — the exact
  /// event the fingerprint exists to notice — invalidates it without hashing on
  /// every start.
  Future<({String? sha256, ExecutableStat? stat})> fingerprintForProfile(
    String profileId,
    String path,
  ) async {
    await init();
    final stat = await statExecutable(path);
    if (stat == null) return (sha256: null, stat: null);
    final cache = await _fingerprintCache();
    final entry = cache[profileId];
    if (entry != null && entry.stat == stat && entry.sha256 != null) {
      return (sha256: entry.sha256, stat: stat);
    }
    final digest = await sha256OfFile(path);
    if (digest != null) {
      cache[profileId] = _FingerprintEntry(stat, digest);
      await _writeFingerprintCache(cache);
    }
    return (sha256: digest, stat: stat);
  }

  Future<Map<String, _FingerprintEntry>> _fingerprintCache() async {
    final raw = await storage.read(kBenchmarkFingerprintKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, _FingerprintEntry>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          final map = Map<String, dynamic>.from(value);
          final stat = map['stat'];
          result['$key'] = _FingerprintEntry(
            stat is Map ? ExecutableStat.fromJson(Map<String, dynamic>.from(stat)) : const ExecutableStat(sizeBytes: 0, modifiedMillis: 0),
            map['sha256'] is String ? map['sha256'] as String : null,
          );
        }
      });
      return result;
    } catch (_) {
      // A broken cache only costs one re-hash.
      return {};
    }
  }

  Future<void> _writeFingerprintCache(
      Map<String, _FingerprintEntry> cache) async {
    await storage.write(
      kBenchmarkFingerprintKey,
      jsonEncode({
        for (final entry in cache.entries)
          entry.key: {
            'stat': entry.value.stat.toJson(),
            if (entry.value.sha256 != null) 'sha256': entry.value.sha256,
          }
      }),
    );
  }

  // ------------------------------------------------------------------ helpers

  static String _checksumOf(Map<String, dynamic> payload) =>
      crypto.sha256.convert(utf8.encode(jsonEncode(payload))).toString();

  /// Everything the store has written, for a "storage used" line.
  Future<int> documentCount() async {
    await init();
    return (await storage.keys(kBenchmarkRunPrefix)).length;
  }
}
