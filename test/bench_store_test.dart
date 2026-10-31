// The benchmark history on disk.
//
// A benchmark run takes minutes and cannot be repeated exactly, so the history
// is the only record of it. The rules this file pins down:
//
//  * a save is atomic and keeps the previous version, so a crash cannot leave
//    half a run in place;
//  * a corrupt document is archived and recovered from the last good copy, not
//    deleted along with it;
//  * a document from a newer build is refused and left alone, never downgraded;
//  * an import never overwrites an existing run, and never loses the one it is
//    importing;
//  * deleting a run deletes its bytes, including the recovery copy.
//
// The file backend is exercised directly against a temporary directory, so the
// atomic-write and recovery rules are tested rather than assumed.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_storage_io.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

/// Storage with a separate recovery copy per key, like both real backends.
///
/// The in-memory backend deliberately keeps none, so it cannot exercise the
/// recovery path; this one behaves like the file and prefs backends and lets a
/// test corrupt either copy.
class BackedStorage extends BenchmarkStorage {
  final Map<String, String> primary = {};
  final Map<String, String> backup = {};
  int writes = 0;

  @override
  Future<void> init() async {}

  @override
  Future<String?> read(String key) async => primary[key];

  @override
  Future<String?> readBackup(String key) async => backup[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    final existing = primary[key];
    if (existing != null && existing.isNotEmpty) backup[key] = existing;
    primary[key] = value;
  }

  /// Recovery writes the primary only: the recovery copy stays the known-good
  /// one instead of being overwritten with the corrupt primary.
  @override
  Future<void> restore(String key, String value) async {
    primary[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    primary.remove(key);
    backup.remove(key);
  }

  @override
  Future<List<String>> keys(String prefix) async => [
        for (final key in [...primary.keys, ...backup.keys])
          if (key.startsWith(prefix)) key
      ];
}

String _runKey(String id) => '$kBenchmarkRunPrefix$id';

void main() {
  late BackedStorage storage;
  late BenchmarkStore store;
  late BenchmarkRun run;

  setUp(() async {
    storage = BackedStorage();
    store = BenchmarkStore(storage: storage);
    run = (await runScriptedBenchmark()).run;
  });

  group('saving', () {
    test('a saved run is listed, loadable and complete', () async {
      await store.saveRun(run);

      final summaries = await store.summaries();
      expect(summaries, hasLength(1));
      expect(summaries.single.id, run.id);
      expect(summaries.single.gamesPlayed, run.gamesPlayed);

      final loaded = await store.loadRun(run.id);
      expect(loaded, isNotNull);
      expect(loaded!.games.length, run.games.length);
      expect(loaded.engines.map((e) => e.engineId),
          run.engines.map((e) => e.engineId));
      expect(loaded.stopReason, run.stopReason);
    });

    test('the stored document carries a schema and a checksum', () async {
      await store.saveRun(run);
      final decoded = jsonDecode(storage.primary[_runKey(run.id)]!) as Map;
      expect(decoded['schema'], kBenchmarkStoreSchema);
      expect(decoded['checksum'], isA<String>());
      expect(decoded['payload'], isA<Map>());
    });

    test('the second save keeps the first as the recovery copy', () async {
      await store.saveRun(run);
      final first = storage.primary[_runKey(run.id)];
      await store.saveRun(run);
      expect(storage.backup[_runKey(run.id)], first);
    });

    test('the identities are remembered for the version-change trigger',
        () async {
      await store.saveRun(run);
      final known = await store.knownIdentities();
      expect(known.keys, containsAll(run.engines.map((e) => e.engineId)));
      expect(known.values.first.engineVersion, '1.0');
    });

    test('concurrent saves do not interleave into a broken document',
        () async {
      final second = (await runScriptedBenchmark(alphaName: 'Gamma')).run;
      await Future.wait([store.saveRun(run), store.saveRun(second)]);
      expect(await store.loadRun(run.id), isNotNull);
      expect(await store.loadRun(second.id), isNotNull);
      expect(await store.summaries(), hasLength(2));
    });
  });

  group('corruption', () {
    test('a corrupt primary is recovered from the recovery copy', () async {
      await store.saveRun(run);
      await store.saveRun(run); // creates the .bak
      storage.primary[_runKey(run.id)] = '{"schema":1,"payload":';

      final good = storage.backup[_runKey(run.id)];
      final loaded = await store.loadRun(run.id);
      expect(loaded, isNotNull);
      expect(loaded!.id, run.id);
      // The good copy is put back, so recovery happens once rather than on
      // every load — and the recovery copy itself survives, so a second
      // corruption is still survivable.
      expect(storage.primary[_runKey(run.id)], good);
      expect(storage.backup[_runKey(run.id)], good);
      // And the bad bytes are kept for diagnosis.
      expect(await store.quarantined(), isNotEmpty);
    });

    test('a checksum mismatch is treated as corruption, not as data',
        () async {
      await store.saveRun(run);
      await store.saveRun(run);
      final decoded = jsonDecode(storage.primary[_runKey(run.id)]!) as Map;
      (decoded['payload'] as Map)['stopReason'] = 'tampered';
      storage.primary[_runKey(run.id)] = jsonEncode(decoded);

      final loaded = await store.loadRun(run.id);
      expect(loaded, isNotNull);
      expect(loaded!.stopReason, run.stopReason);
      expect(await store.quarantined(), isNotEmpty);
    });

    test('with both copies gone the run is dropped from the index', () async {
      await store.saveRun(run);
      final key = _runKey(run.id);
      storage.primary[key] = 'not json';
      storage.backup[key] = 'also not json';

      expect(await store.loadRun(run.id), isNull);
      expect(await store.summaries(), isEmpty,
          reason: 'an unreadable run must not stay in the list');
    });

    test('a document from a newer build is refused and left untouched',
        () async {
      await store.saveRun(run);
      final key = _runKey(run.id);
      final decoded = jsonDecode(storage.primary[key]!) as Map;
      decoded['schema'] = kBenchmarkStoreSchema + 1;
      final newer = jsonEncode(decoded);
      storage.primary[key] = newer;
      storage.backup[key] = 'older but readable';

      expect(await store.loadRun(run.id), isNull);
      expect(storage.primary[key], newer,
          reason: 'a newer document must not be replaced or archived');
      expect(await store.quarantined(), isEmpty);
    });

    test('an absent run is not corruption', () async {
      expect(await store.loadRun('never-existed'), isNull);
      expect(await store.quarantined(), isEmpty);
    });
  });

  group('deleting', () {
    test('removes the document, the recovery copy and the index entry',
        () async {
      await store.saveRun(run);
      await store.saveRun(run);
      expect(storage.backup, isNotEmpty);

      expect(await store.deleteRun(run.id), isTrue);
      // The index and the identity cache stay; the run's own bytes do not.
      expect(storage.primary.keys.where((k) => k.startsWith(kBenchmarkRunPrefix)),
          isEmpty);
      expect(storage.backup.keys.where((k) => k.startsWith(kBenchmarkRunPrefix)),
          isEmpty,
          reason: 'a deleted run must not survive in a recovery copy');
      expect(await store.summaries(), isEmpty);
    });

    test('a run that is not there reports false', () async {
      expect(await store.deleteRun('missing'), isFalse);
    });
  });

  group('export and import', () {
    test('a single run exports and imports into a fresh store unchanged',
        () async {
      await store.saveRun(run);
      final exported = await store.exportRunJson(run.id);
      expect(exported, isNotNull);

      final other = BenchmarkStore(storage: BackedStorage());
      final results = await other.importJson(exported!);
      expect(results, hasLength(1));
      expect(results.single.idChanged, isFalse);
      expect(results.single.run.id, run.id);
      expect((await other.summaries()).single.id, run.id);
      expect((await other.loadRun(run.id))!.games.length, run.games.length);
    });

    test('a full backup round-trips every run', () async {
      final second = (await runScriptedBenchmark(alphaName: 'Gamma')).run;
      await store.saveRun(run);
      await store.saveRun(second);
      final backup = await store.exportAllJson();

      final other = BenchmarkStore(storage: BackedStorage());
      final results = await other.importJson(backup);
      expect(results, hasLength(2));
      expect(await other.summaries(), hasLength(2));
    });

    test('importing a run that already exists does not overwrite it', () async {
      await store.saveRun(run);
      final before = storage.primary[_runKey(run.id)];

      final results = await store.importJson(await store.exportRunJson(run.id)
          as String);
      expect(results.single.idChanged, isTrue);
      expect(results.single.warnings.join(' '), contains('already exists'));
      expect(storage.primary[_runKey(run.id)], before,
          reason: 'the existing run must be untouched');
      expect(await store.summaries(), hasLength(2));
    });

    test('a hand-edited document imports with a warning, not silently',
        () async {
      await store.saveRun(run);
      final decoded =
          jsonDecode(await store.exportRunJson(run.id) as String) as Map;
      (decoded['payload'] as Map)['stopReason'] = 'edited by hand';
      final other = BenchmarkStore(storage: BackedStorage());
      final results = await other.importJson(jsonEncode(decoded));
      expect(results.single.warnings.join(' '), contains('Checksum mismatch'));
      expect(results.single.run.stopReason, 'edited by hand');
    });

    test('nonsense is rejected with a message, not an exception type leak',
        () async {
      await expectLater(store.importJson('not json'),
          throwsA(isA<FormatException>()));
      await expectLater(store.importJson('[]'),
          throwsA(isA<FormatException>()));
      await expectLater(store.importJson('{"hello": 1}'),
          throwsA(isA<FormatException>()));
      await expectLater(
        store.importJson('{"schema":1,"payload":{"id":"x"}}'),
        throwsA(isA<FormatException>()),
        reason: 'a payload without games is not a run',
      );
    });

    test('a newer document is refused by the importer too', () async {
      await store.saveRun(run);
      final decoded =
          jsonDecode(await store.exportRunJson(run.id) as String) as Map;
      decoded['schema'] = kBenchmarkStoreSchema + 1;
      final other = BenchmarkStore(storage: BackedStorage());
      await expectLater(
          other.importJson(jsonEncode(decoded)), throwsA(isA<FormatException>()));
    });
  });

  group('privacy', () {
    test('no stored field names a filesystem path', () async {
      await store.saveRun(run);
      final exported =
          jsonDecode(await store.exportRunJson(run.id) as String) as Map;
      final keys = <String>{};
      void walk(Object? value) {
        if (value is Map) {
          for (final entry in value.entries) {
            keys.add('${entry.key}'.toLowerCase());
            walk(entry.value);
          }
        } else if (value is List) {
          for (final item in value) {
            walk(item);
          }
        }
      }

      walk(exported);
      for (final forbidden in ['path', 'file', 'executable', 'directory']) {
        expect(keys.where((k) => k.contains(forbidden)), isEmpty,
            reason: 'a run must not carry "$forbidden"');
      }
    });

    test('a hostile engine name cannot leave the storage directory', () async {
      final hostile = (await runScriptedBenchmark(alphaName: '../escape')).run;
      await store.saveRun(hostile);
      // Keys are the store's own; the name never becomes a path.
      final keys = await storage.keys(kBenchmarkRunPrefix);
      expect(keys, everyElement(isNot(contains('..'))));
    });
  });

  group('file storage', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('bench_store'));
    tearDown(() => directory.deleteSync(recursive: true));

    FileBenchmarkStorage backend() =>
        FileBenchmarkStorage(directoryName: 'bench', rootOverride: directory);

    test('writes atomically and keeps the previous copy', () async {
      final files = backend();
      await files.init();
      await files.write('doc', 'first');
      expect(await files.read('doc'), 'first');
      await files.write('doc', 'second');
      expect(await files.read('doc'), 'second');
      expect(await files.readBackup('doc'), 'first');
      // No temporary file is left behind.
      final names = directory
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      expect(names, contains('doc.json'));
      expect(names, contains('doc.json.bak'));
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
    });

    test('a missing primary falls back to the recovery copy', () async {
      final files = backend();
      await files.init();
      await files.write('doc', 'first');
      await files.write('doc', 'second');
      File('${directory.path}/bench/doc.json').deleteSync();
      expect(await files.read('doc'), 'first');
    });

    test('restoring a recovered document keeps the recovery copy', () async {
      final files = backend();
      await files.init();
      await files.write('doc', 'first');
      await files.write('doc', 'second'); // .bak is now "first"
      await files.restore('doc', 'first');
      expect(await files.read('doc'), 'first');
      expect(await files.readBackup('doc'), 'first',
          reason: 'a recovery must not overwrite the last good copy with the '
              'corrupt one it is replacing');
    });

    test('delete removes both copies', () async {
      final files = backend();
      await files.init();
      await files.write('doc', 'first');
      await files.write('doc', 'second');
      await files.delete('doc');
      expect(await files.read('doc'), isNull);
      expect(await files.readBackup('doc'), isNull);
    });

    test('a key cannot escape the directory', () async {
      final files = backend();
      await files.init();
      for (final key in ['../escape', 'a/b', r'a\b', '..', '']) {
        await expectLater(files.write(key, 'x'), throwsA(isA<ArgumentError>()),
            reason: 'key "$key"');
      }
    });

    test('keys lists documents by prefix and ignores backups', () async {
      final files = backend();
      await files.init();
      await files.write('run.one', 'x');
      await files.write('run.one', 'y');
      await files.write('index', 'z');
      expect(await files.keys('run.'), ['run.one']);
    });
  });
}
